# Sentinel Prototype - Copilot Instructions

## Project Overview

**Sentinel Prototype** is a top-down 2D multiplayer survival game (Rust-like progression) with humans vs machines, PvP/raiding, and scavenging sandbox mechanics.

- **Engine**: Godot 4.4.1
- **Language**: GDScript
- **Live**: https://woolachee.itch.io/sentinel
- **Server**: Railway.app (WebSocket/ENet dual protocol)

---

## Architecture

### Core Concept: Hybrid Client-Server Model

The game uses **different prediction strategies per entity type** to balance responsiveness and consistency:

| Entity | Strategy | Latency | Applies To |
|--------|----------|---------|-----------|
| Local Player | Client-Side Prediction + Reconciliation | ~0ms | You |
| Remote Players | Interpolation (2 tick delay) | ~33ms | Others |
| Enemies | Interpolation (2 tick delay) | ~33ms | AI entities |
| Walls | Static (health-only sync) | 0ms | Structures |
| Bullets | Pure Client Prediction | 0ms | Projectiles |

**Why**: Local player needs instant feedback; others render from server truth with smoothing.

### Key Files Structure

```
scripts/
├── Bootstrap.gd                      # Entry point (--server/--client mode)
├── client/ClientMain.gd              # Prediction, interpolation, reconciliation
├── server/ServerMain.gd              # Authoritative simulation, snapshot broadcast
├── net/Net.gd                        # Dual protocol transport (WebSocket/ENet)
├── shared/
│   ├── NetworkedEntity.gd           # Base class for all replicated entities
│   ├── ReplicationManager.gd        # Entity registry, snapshot building
│   ├── GameConstants.gd             # Shared physics constants
│   └── WeaponData.gd                # Weapon definitions
├── entities/
│   ├── Player.gd                    # Player logic (movement, shooting, building)
│   ├── Enemy.gd                     # AI enemies (aggro system)
│   ├── Bullet.gd                    # Projectiles
│   └── Wall.gd                      # Buildable structures
├── systems/
│   ├── Log.gd                       # Categorized logging (autoload)
│   ├── PersistenceAPI.gd            # Save/load abstraction
│   └── JSONPersistence.gd           # JSON backend (switchable to SQLite)
└── components/
    └── Weapon.gd                    # Weapon component (ammo, reload)
```

### Autoload Singletons (in project.godot)

```gdscript
Log              # Logging system with categories
Net              # Networking singleton (RPC routing)
Replication      # Entity registry & snapshot management
Persistence      # Save/load abstraction layer
```

---

## Network Data Flow

```
CLIENT TICK 0:
  - Sample input (movement, aim, buttons)
  - Send to server via RPC
  - Predict locally (apply movement immediately)
  - Store predicted state

SERVER TICK 1:
  - Receive client input
  - Simulate all entities (players, enemies, bullets)
  - Build snapshot (all entity states)
  - Broadcast snapshot + per-client ACK

CLIENT TICK 2:
  - Receive snapshot → Apply health immediately
  - Buffer remote entity states for interpolation
  - Receive ACK → Compare predicted vs server position
  - If mismatch > RECONCILE_POSITION_THRESHOLD (5.0): rewind & replay inputs

CLIENT TICK 4:
  - Interpolate remote entities between buffered snapshots
  - Render at (current_tick - 2) for smooth animation
```

### Data Structures

**Snapshot Format**:
```gdscript
{
  "123": {"p": Vector2(100, 50), "r": 0.5, "h": 80.0},  # net_id: replicated_state
  "456": {"p": Vector2(200, 100), "r": 1.0, "h": 150.0}
}
```

**Input Format**:
```gdscript
{
  "mv": Vector2(-1, 0),      # movement_vector
  "aim": Vector2(1, 0),      # normalized aim direction
  "btn": 0x01                # button flags (BTN_SHOOT | BTN_BUILD)
}
```

**Entity Replication** (override in subclasses):
```gdscript
func get_replicated_state() -> Dictionary:
    return {"p": global_position, "r": rotation, "h": health}

func apply_replicated_state(state: Dictionary) -> void:
    global_position = state.get("p", global_position)
    rotation = state.get("r", rotation)
    health = state.get("h", health)
```

---

## Critical Developer Workflows

### Local Testing

```bash
# Terminal 1: Server (headless)
run_server.bat                    # Windows
# or bash: start.sh              # Linux/Mac

# Terminal 2: Client 1
run_client.bat --auto-connect

# Terminal 3: Client 2
run_client.bat --auto-connect
```

### Network Debugging

**Press F3** in client to toggle debug overlay:
- FPS (60-sample average)
- Ping (round-trip milliseconds)
- Snapshot delivery % (loss detection)
- Reconciles/sec (prediction mismatches)
- Entity counts (total + interpolated)

**Runtime logging** (in code):
```gdscript
Log.network("Connected to server")      # Network events
Log.entity("Spawned player %d" % id)    # Entity lifecycle
Log.reconcile("Position mismatch: %v" % delta)  # Debug predictions
Log.set_verbose(true)                   # Enable all categories
```

### Entity Persistence (Server-Only)

Walls save automatically via `Persistence` API:
```gdscript
# Save
Persistence.save_structure({
  "net_id": 10001,
  "pos": Vector2(100, 50),
  "health": 150.0
})

# Load (on server startup)
var structures = Persistence.load_all_structures()
for data in structures:
  _spawn_wall_from_data(data)
```

---

## Project-Specific Conventions

### GameConstants.gd

All physics/balance values centralized here. **Changes sync automatically** on both server/client since it's a shared file:
```gdscript
const PLAYER_MOVE_SPEED = 220.0
const PLAYER_DASH_SPEED = 1000.0
const ENEMY_AGGRO_RANGE = 600.0
const BULLET_DAMAGE = 25.0
const INTERP_DELAY_TICKS = 2  # Snapshot buffer delay
```

### Entity Authority System

Every `NetworkedEntity` has an `authority` field:
- `authority == 1`: Server owns entity (all players/enemies/bullets)
- `authority == peer_id`: Client owns for prediction (local player only)

```gdscript
func is_authority() -> bool:
    if Net.is_server():
        return authority == 1
    else:
        return authority == Net.get_unique_id()
```

### Weapon System

Weapons are components with data dictionaries:
```gdscript
# WeaponData.gd (definitions)
static var PISTOL = {
  "name": "Pistol",
  "damage": 25.0,
  "fire_rate": 0.1,
  "ammo": 30,
  "pellets": 1,
  "spread": 0.0
}

# Player.gd (usage)
var equipped_weapon: Weapon
if equipped_weapon.shoot():  # Respects cooldown/ammo
  var damage = equipped_weapon.data.get("damage", GameConstants.BULLET_DAMAGE)
```

### Enemy Aggro Tracking

Enemies track damage-per-attacker to determine target:
```gdscript
var _damage_taken: Dictionary = {}  # player_id -> damage
var _aggro_target: Player = null
var _aggro_lock_time: float = 0.0

const ENEMY_AGGRO_RANGE = 600.0
const ENEMY_AGGRO_LOCK_TIME = 3.0
```

---

## Integration Points

### Client-Server Communication (RPCs)

Defined in `Net.gd`. Usage example from `ClientMain._send_input()`:
```gdscript
Net.server_receive_input.rpc(input_dict)
```

Server broadcasts snapshots:
```gdscript
# ServerMain._broadcast_snapshot()
Net.client_receive_snapshot.rpc(snapshot)
Net.client_receive_ack.rpc(ack_dict)
```

### Replication Workflow

1. **Entity spawns**: Calls `super._ready()` → Auto-registered in `ReplicationManager`
2. **Server builds snapshot**: `Replication.build_snapshot()` calls `get_replicated_state()` on each entity
3. **Client receives**: `apply_replicated_state()` called by `ClientMain._process_snapshot()`
4. **Static entities**: Walls get periodic sync via `STATIC_SNAPSHOT_INTERVAL` (5.0 sec)

### Persistence Backend

Abstraction allows swapping implementations:
```gdscript
# PersistenceAPI.gd (autoload)
var _backend: PersistenceBackend  # JSONPersistence or SQLitePersistence

# Call same API, different backends
Persistence.save_structure(data)
```

Currently: **JSONPersistence** (human-readable)  
Future: SQLite (when >50 players or performance needed)

---

## Common Patterns

### Prediction Reconciliation

If local player position diverges from server ACK:
```gdscript
# ClientMain._process_ack()
if global_position.distance_to(ack_pos) > GameConstants.RECONCILE_POSITION_THRESHOLD:
  # Rewind to last confirmed state, replay pending inputs
  _reconcile_player()
  _reconciles_per_sec += 1
```

### Health & Non-Predicted State

Health **always applied immediately** from snapshot, never reconciled:
```gdscript
# ClientMain._process_snapshot()
_my_player.health = snap_state.get("h", _my_player.health)
```

### Interpolation for Remote Entities

Remote players/enemies render from 2-tick-delayed buffer:
```gdscript
# ClientMain._interpolate_entities()
var entity_snap = _snap_buffers[net_id][-2]  # 2 ticks back
entity.apply_replicated_state(entity_snap)
```

---

## Build & Deployment

### Local Build (Export)

From Godot editor: **Project → Export** (HTML5 for web)

### Server Deploy (Railway.app)

Triggered by push to repository:
1. Railway detects `railway.json` config
2. Runs `bash start.sh` (downloads Godot 4.4.1, runs server)
3. Listens on `0.0.0.0:443` (HTTPS/WebSocket)

**Check logs**: Railway dashboard → Deployments → View logs

---

## Testing Checklist

Before submitting changes:

- [ ] **Prediction**: Local player movement feels instant (no latency)
- [ ] **Reconciliation**: No rubber-banding when ping varies
- [ ] **Interpolation**: Remote players move smoothly (not teleporting)
- [ ] **Network loss**: Game handles dropped snapshots gracefully
- [ ] **Persistence**: Server restart reloads walls/structures
- [ ] **Authority**: Only server can damage; clients reject invalid actions
- [ ] **Constants**: All balance values in `GameConstants.gd`, not hardcoded

---

## Quick Reference: When to Modify Key Files

| Task | File | Notes |
|------|------|-------|
| Add player mechanic | `Player.gd` | Override `apply_input()` and `get_replicated_state()` |
| Add enemy AI | `Enemy.gd` | Modify `_update_ai()` and aggro logic |
| Adjust physics/balance | `GameConstants.gd` | Changes sync to all clients automatically |
| Change network transport | `Net.gd` + `GameConstants.USE_WEBSOCKET` | Toggle ENet ↔ WebSocket |
| Add persistence (player data) | `JSONPersistence.gd` | Implement `load_player()` / `save_player()` |
| Debug prediction issues | `ClientMain.gd` + `Log.reconcile()` | Press F3 for overlay, enable RECONCILE logs |
| Add new entity type | Create `scripts/entities/NewEntity.gd` extending `NetworkedEntity` | Must implement `get_replicated_state()` |
