# ARCHITECTURE.md - Sentinel Prototype Technical Architecture

## Overview

Sentinel is a top-down 2D multiplayer survival game built with Godot 4.4.1. The architecture uses authoritative server simulation with client-side prediction and interpolation for responsive networked gameplay.

---

## Core Architecture Principles

### 1. Component-Based Networking (Refactored Session #5)

**Pattern**: Composition over inheritance for flexible entity design.

```gdscript
# NetworkedEntity.gd - Pure component (RefCounted)
class_name NetworkedEntity
extends RefCounted

var net_id: int
var authority: int
var entity_type: String
var owner_node: Node2D  # Reference to actual entity

# Player.gd - Entity IS the physics body
extends CharacterBody2D
class_name Player

var net_entity: NetworkedEntity  # Holds component
var health: float
var username: String

func _ready():
    # Create networking component
    net_entity = NetworkedEntity.new(self, net_id, authority, "player")
    
    # Setup collision directly
    collision_layer = 2
    collision_mask = 1 | 2
    
    # Movement is simple - native Godot physics
    func apply_input(movement, dt):
        velocity = movement * MOVE_SPEED
        move_and_slide()  # That's it!
```

**Benefits:**
- ✅ Entities extend their proper physics body types (CharacterBody2D, StaticBody2D, Area2D)
- ✅ NetworkedEntity is opt-in component for replication
- ✅ No position syncing - entities ARE their physics bodies
- ✅ Clean separation: physics vs networking
- ✅ Type-safe (player is CharacterBody2D works)
- ✅ Godot-idiomatic (composition over inheritance)

---

## Entity Types

### Player (CharacterBody2D)
- **Authority**: Client-predicted (local player) or server-authoritative (remote players)
- **Movement**: Client-side prediction with server reconciliation
- **Collision**: Layer 2, masks 1|2 (walls + players)
- **Features**: Weapons, stamina, dash, sprint, building

### Enemy (CharacterBody2D)
- **Authority**: Server-authoritative
- **Movement**: Server AI with client interpolation
- **Collision**: Layer 3 (bit value 4), masks 1|4 (walls + enemies)
- **Types**: Normal, Scout, Tank, Sniper, Swarm
- **AI**: Chase, Wander, Separate states with aggro system

### Wall (StaticBody2D)
- **Authority**: Server-authoritative
- **Movement**: Static (no interpolation needed)
- **Collision**: Layer 1, mask 0
- **Features**: Health, ownership, persistence

### Bullet (Node2D)
- **Authority**: Client-predicted
- **Movement**: Linear velocity
- **Collision**: Raycasting (not physics layers)
- **Lifespan**: 2 seconds, destroyed on impact

---

## Network Architecture

### Server (Authoritative)

**Responsibilities:**
- Simulate all entities at 60 FPS fixed timestep
- Apply player inputs to server-side player entities
- Run enemy AI
- Validate bullet collisions and damage
- Persist player data and structures
- Send snapshots to all clients

**Flow:**
```
1. Receive player inputs (unreliable RPC)
2. Apply inputs to server player entities
3. Simulate enemies, bullets, walls
4. Build snapshot of all entity states
5. Send snapshot to all clients (unreliable RPC)
6. Send ACK to each client (unreliable RPC)
```

### Client (Prediction + Interpolation)

**Responsibilities:**
- Predict local player movement instantly
- Interpolate remote entities smoothly
- Reconcile prediction errors
- Render at 60 FPS

**Strategies by Entity Type:**

| Entity Type | Strategy | Why |
|-------------|----------|-----|
| Local Player | Client-side prediction | Zero-latency input response |
| Remote Players | Interpolation (2 ticks behind) | Smooth movement without inputs |
| Enemies | Interpolation (2 ticks behind) | Server-authoritative AI |
| Walls | Static (health-only updates) | Don't move, no interpolation needed |
| Bullets | Pure client prediction | Instant visual feedback |

**Flow:**
```
1. Sample input → Send to server → Predict locally → Store state
2. Server snapshot → Buffer for interpolation → Apply health immediately
3. Server ACK → Check position → Reconcile if mismatch
4. Every frame → Interpolate remote entities between buffered snapshots
```

---

## Replication System

### ReplicationManager (Autoload)

**Purpose**: Central registry for all networked entities

```gdscript
# ReplicationManager.gd
var _entities: Dictionary = {}  # net_id -> NetworkedEntity component

func register_entity(entity: NetworkedEntity):
    _entities[entity.net_id] = entity

func get_entity(net_id: int) -> Node2D:
    var component = _entities.get(net_id)
    return component.owner_node if component else null

func build_snapshot() -> Dictionary:
    var states = {}
    for id in _entities:
        if _entities[id].authority == 1:  # Server-authoritative only
            states[id] = _entities[id].get_replicated_state()
    return states
```

**Entity Registration:**
```gdscript
# Automatic on spawn
func _ready():
    net_entity = NetworkedEntity.new(self, net_id, authority, "player")
    # Registration happens in NetworkedEntity._init()

# Automatic cleanup on despawn
func _exit_tree():
    if net_entity:
        net_entity.unregister()
```

---

## Collision System

### Physics Layers

| Layer | Bit Value | Name | Entities |
|-------|-----------|------|----------|
| 1 | 1 | STATIC | Walls, terrain |
| 2 | 2 | PLAYER | Players |
| 3 | 4 | ENEMY | Enemies |
| 4 | 8 | PROJECTILE | Bullets (unused - raycasting) |

### Collision Matrix

|        | STATIC | PLAYER | ENEMY |
|--------|--------|--------|-------|
| PLAYER | ✓ | ✓ | ✗ |
| ENEMY  | ✓ | ✗ | ✓ |

**Design Decision**: Players and enemies don't collide to prevent:
- Body-blocking griefing
- Enemy swarm pathfinding issues
- Combat is ranged, not melee

### Movement Pattern

```gdscript
# Player.gd / Enemy.gd
func apply_input(movement: Vector2, dt: float):
    # Calculate velocity
    velocity = movement * MOVE_SPEED
    
    # Move with collision - NATIVE GODOT!
    move_and_slide()
    
    # Optional: clamp to world bounds
    global_position = global_position.clamp(WORLD_MIN, WORLD_MAX)
```

**No position syncing required** - entities ARE their physics bodies.

---

## Prediction & Reconciliation

### Client-Side Prediction (Local Player Only)

**Why**: Instant input response (zero perceived latency)

**Process:**
1. Sample input every frame
2. Send to server (unreliable RPC)
3. Apply input locally immediately
4. Store predicted state with sequence number
5. Keep pending inputs for reconciliation

```gdscript
# ClientMain.gd
func _send_and_predict(dt):
    _input_seq += 1
    var cmd = {"seq": _input_seq, "mv": movement, "aim": aim, "btn": buttons}
    
    # Send to server
    Net.server_receive_input.rpc_id(1, cmd)
    
    # Predict locally
    player.apply_input(cmd.mv, cmd.aim, cmd.btn, dt)
    
    # Store for reconciliation
    _pending_inputs.append(cmd)
    _predicted_states[_input_seq] = player.get_replicated_state()
```

### Server Reconciliation

**When**: Server ACK arrives with confirmed sequence number

**Process:**
1. Compare predicted position with server position
2. If mismatch > threshold (5 pixels):
   - Rewind to server state
   - Replay all pending inputs after ACK
   - Re-predict all states
3. If match: just drop confirmed inputs

```gdscript
# ClientMain.gd
func _on_ack(ack):
    var predicted_pos = _predicted_states[ack.seq].p
    var server_pos = _last_server_state.p
    
    if predicted_pos.distance_to(server_pos) >= 5.0:
        # Reconcile: rewind and replay
        player.apply_replicated_state(_last_server_state)
        
        for cmd in _pending_inputs:
            if cmd.seq > ack.seq:
                player.apply_input(cmd.mv, cmd.aim, cmd.btn, FIXED_DELTA)
                _predicted_states[cmd.seq] = player.get_replicated_state()
```

**What's NOT reconciled**: Health, stamina (applied immediately from snapshots)

---

## Interpolation (Remote Entities)

### Buffer-Based Interpolation

**Why**: Smooth movement despite network jitter

**Process:**
1. Receive snapshot from server
2. Add to per-entity buffer (keyed by net_id)
3. Render 2 ticks behind (`_latest_tick - 2`)
4. Lerp between surrounding snapshots

```gdscript
# ClientMain.gd
func _interpolate_entity(entity: Node2D, render_tick: int):
    var buf = _snap_buffers[entity.net_id]
    
    # Find surrounding snapshots
    var a = buf[i]      # Earlier snapshot
    var b = buf[i+1]    # Later snapshot
    
    # Calculate lerp factor
    var t = (render_tick - a.tick) / (b.tick - a.tick)
    
    # Interpolate position/rotation
    entity.position = a.state.p.lerp(b.state.p, t)
    entity.rotation = lerp_angle(a.state.r, b.state.r, t)
    
    # Apply health immediately (no interpolation)
    entity.health = b.state.h
```

**Entities Interpolated**: Remote players, enemies  
**Entities NOT Interpolated**: Walls (static), bullets (client-predicted), local player (predicted)

---

## Persistence System

### JSON Backend (Current)

**Storage:**
- `user://saves/players/{username}.json` - One file per player
- `user://saves/structures.json` - All structures

**When Data is Saved:**
- Player connect/disconnect
- Autosave every 30 seconds
- Server shutdown (graceful)
- Admin commands (F5/F6 wipe)

**What's Persisted:**

**Players:**
```json
{
  "username": "Alice",
  "position_x": 512.0,
  "position_y": 300.0,
  "health": 100.0,
  "level": 1,
  "xp": 0,
  "reputation": 0.0,
  "currency": 0,
  "last_login": 1234567890
}
```

**Structures:**
```json
{
  "id": 1,
  "owner_username": "Alice",
  "type": "wall",
  "position_x": 512.0,
  "position_y": 300.0,
  "health": 200.0,
  "created_at": 1234567890
}
```

### Future: SQLite Migration

**Trigger**: When concurrent players exceeds 50  
**Why**: Better query performance, relational data, concurrent access  
**Abstraction**: `PersistenceBackend` interface ready for swap

---

## File Structure

```
scripts/
├── Bootstrap.gd                  # Entry point (--server/--client)
├── systems/
│   └── Log.gd                    # Logging system (autoload)
├── shared/
│   ├── NetworkedEntity.gd        # Component (RefCounted)
│   ├── ReplicationManager.gd     # Entity registry (autoload)
│   ├── GameConstants.gd          # Shared constants
│   └── WeaponData.gd             # Weapon definitions
├── entities/
│   ├── Player.gd                 # CharacterBody2D
│   ├── Enemy.gd                  # CharacterBody2D
│   ├── Wall.gd                   # StaticBody2D
│   └── Bullet.gd                 # Node2D
├── components/
│   └── Weapon.gd                 # Weapon system
├── server/
│   └── ServerMain.gd             # Authoritative simulation
├── client/
│   └── ClientMain.gd             # Prediction + interpolation
├── net/
│   └── Net.gd                    # Network transport (autoload)
└── persistence/
    ├── Persistence.gd            # Persistence API (autoload)
    ├── PersistenceBackend.gd     # Interface
    └── JSONBackend.gd            # JSON implementation
```

---

## Network Protocol

### RPCs (Remote Procedure Calls)

**Client → Server:**
- `server_receive_input(cmd)` - Unreliable, every frame
- `server_receive_username(username)` - Reliable, once on connect

**Server → Client:**
- `client_receive_snapshot(snap)` - Unreliable, 60 FPS
- `client_receive_ack(ack)` - Unreliable, 60 FPS
- `client_spawn_player(payload)` - Reliable, on player connect
- `client_despawn_player(peer_id)` - Reliable, on player disconnect
- `spawn_entity(data)` - Reliable, for enemies/walls/bullets
- `despawn_entity(net_id)` - Reliable, for entity destruction
- `client_receive_static_snapshot(states)` - Reliable, every 5 seconds

### Transport Layer

**Dual Protocol Support:**
- **WebSocket** (default): For web builds, Railway deployment
- **ENet**: For native builds, local testing

**Configuration:**
```gdscript
# GameConstants.gd
const USE_WEBSOCKET: bool = true
```

---

## Performance Optimizations

### Current Optimizations

1. **Wall Static Snapshot**: Walls sent separately every 5s (reliable) instead of every frame
2. **Entity Culling**: Bullets skip interpolation entirely
3. **Snapshot Buffering**: Only keep last 40 snapshots per entity
4. **Input Buffering**: Only keep last 256 pending inputs

### Future Optimizations (Not Yet Implemented)

1. **Spatial Partitioning**: Chunk-based entity queries (when >200 entities)
2. **Interest Management**: Only sync nearby entities
3. **Snapshot Compression**: Delta compression for states
4. **Object Pooling**: Reuse bullet/particle objects

---

## Testing & Debugging

### Local Testing

```bash
# Start server + 3 clients
start_test_session.bat

# Single client to localhost
run_client_local.bat Alice
```

### Debug Overlays

**F3**: Network diagnostics
- FPS (60-sample average)
- Tick interval (snapshot rate)
- Ping (round-trip every 10th input)
- Packet loss (snapshot delivery %)
- Reconciles/sec
- Entity counts

**F4**: Collision visualization (Godot built-in)
- Blue boxes: collision shapes
- Red lines: raycasts

### Admin Commands (Server Only)

- **F5**: Wipe all structures
- **F6**: Wipe all player data
- **F7**: Show persistence stats

---

## Known Limitations

1. **World Size**: 1024x600 (small map)
2. **Player Capacity**: ~50 concurrent (JSON backend)
3. **No Spatial Audio**: Sound system not yet implemented
4. **No Fog of War**: Vision system not yet implemented
5. **Single Server**: No horizontal scaling

---

## Future Architecture Plans

### Phase 2: Fog of War (Week 3)
- Raycasting for line-of-sight
- Client-side visibility culling
- Layer 7 (FOG_BLOCKER) for smoke grenades

### Phase 3: Sound System (Week 4)
- Gunshot proximity alerts
- Wall muffling (raycast-based)
- Enemy investigation AI

### Phase 4: Advanced Interaction (Week 5)
- E-key raycasting for pickup
- Door/workbench interaction
- Layer 6 (INTERACTION) for usable objects

### Phase 5: Map Expansion (Week 6+)
- Lawfulness zones (Safe/Neutral/Lawless)
- Territory control points
- Larger world (4096x4096)

---

## Design Philosophy

**Authoritative Server**: Server is source of truth, client predicts for responsiveness  
**Component Pattern**: Composition over inheritance for flexibility  
**Godot-Idiomatic**: Use engine features as intended (physics bodies, move_and_slide)  
**Simplicity**: Minimize complexity, avoid clever hacks  
**Performance**: Optimize only when proven necessary  

---

## Version History

- **Session #1-3**: Initial prototype, weapons, enemies
- **Session #4**: Persistence + username system
- **Session #5**: Component refactor + collision system
- **Session #6**: Loot & inventory (planned)
