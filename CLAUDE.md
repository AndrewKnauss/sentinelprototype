# CLAUDE.md - Persistent Context

## Project Overview
**Sentinel Prototype** - Top-down 2D multiplayer survival (Rust-like progression)  
Humans vs machines + PvP/raiding, scavenging sandbox

**Live Game**: https://woolachee.itch.io/sentinel  
**Server**: web-production-5b732.up.railway.app:443

## Tech Stack
- **Engine**: Godot 4.4.1
- **Language**: GDScript
- **Networking**: WebSocket (default) / ENet (toggle)
- **Hosting**: Railway.app
- **Resolution**: 1920x1080 fullscreen

## Architecture

### Core Files
```
scripts/
├── Bootstrap.gd              # Entry (--server/--client, reads Railway PORT, --auto-connect)
├── client/ClientMain.gd      # Prediction + interpolation + connection UI
├── server/ServerMain.gd      # Authoritative simulation
├── entities/
│   ├── Player.gd            # Networked player (hurt flash, black if local)
│   ├── Enemy.gd             # AI enemy (chase/wander/separate)
│   ├── Bullet.gd            # Client-predicted projectile
│   └── Wall.gd              # Buildable structure
├── shared/
│   ├── NetworkedEntity.gd   # Base replicated entity
│   ├── ReplicationManager.gd # Entity registry
│   └── GameConstants.gd     # Shared constants + USE_WEBSOCKET flag
└── net/Net.gd               # Dual protocol transport (ENet/WebSocket)
```

### Networking Model
**Server**: Authoritative, 60 FPS fixed timestep  
**Client**: Prediction (local player) + Interpolation (remote entities)

**Dual Protocol**:
```gdscript
// GameConstants.gd
const USE_WEBSOCKET: bool = true  // Toggle ENet/WebSocket

// Net.gd - Auto-selects protocol
if GameConstants.USE_WEBSOCKET:
	peer = WebSocketMultiplayerPeer.new()
	var protocol = "wss://" if port == 443 else "ws://"
	peer.create_client(protocol + host + ":" + str(port))
else:
	peer = ENetMultiplayerPeer.new()
	peer.create_client(host, port)
```

**Input Flow**:
1. Client samples input → sends to server
2. Client predicts locally (instant response)
3. Server simulates → sends snapshot
4. Client reconciles if misprediction (checks position + health)

**Entity Types**:
- Players: Client predicts own, interpolates others
- Enemies: Server-authoritative, client interpolates
- Bullets: Client-predicted spawn, client collision, server validates damage
- Walls: Server-authoritative, static (no interpolation, health-only updates)

### Key Systems

**Prediction/Reconciliation**:
```gdscript
_input_seq: int
_pending_inputs: Array
_predicted_states: Dictionary

// Reconciliation checks ALL state
var needs_reconcile = (
	pred_pos.distance_to(srv_pos) >= RECONCILE_POSITION_THRESHOLD or
	abs(pred_health - srv_health) > 0.01
)
```

**Interpolation**:
```gdscript
_snap_buffers: Dictionary  // net_id -> [{tick, state}]
INTERP_DELAY_TICKS: 2

// Remote players and enemies interpolated
// Walls skip interpolation (static, health-only updates)
// Bullets skip interpolation (client-predicted)
```

**Wall Optimization**:
```gdscript
// Walls are static after placement
// Only health updates from snapshots, no position interpolation
if entity is Wall:
    entity.health = state["h"]  // Update health only
    continue  // Skip interpolation buffer
```

**Bullet Handling**:
- Client spawns instantly (net_id=-1, authority=client_id)
- Server spawns authoritative (sends RPC)
- Client skips if owner matches
- Collision runs both sides (visual + authoritative)

**Hurt Flash** (Player.gd):
```gdscript
// Server: take_damage() sets _hurt_flash_timer = 0.2
// Client: apply_replicated_state() detects health drop, sets timer
// _process(): Lerps sprite RED -> base_color over 0.2s

if _hurt_flash_timer > 0.0:
	_hurt_flash_timer -= delta
	var flash_intensity = _hurt_flash_timer / 0.2
	_sprite.modulate = Color.RED.lerp(_get_base_color(), 1.0 - flash_intensity)
```

**Connection UI** (ClientMain.gd):
```gdscript
// Host/port inputs + Connect button
// Defaults: web-production-5b732.up.railway.app:443
// Skipped if --auto-connect flag present
```

**Local Player Visual**:
```gdscript
// Player.gd
func _get_base_color() -> Color:
	return Color.BLACK if is_local else _color_from_id(net_id)
```

## Constants (GameConstants.gd)
```gdscript
USE_WEBSOCKET: true
PHYSICS_FPS: 60
PLAYER_MOVE_SPEED: 220.0
BULLET_SPEED: 800.0
INTERP_DELAY_TICKS: 2
RECONCILE_POSITION_THRESHOLD: 5.0
```

## Deployment (Railway.app)

**Files**:
- `Procfile`: `web: bash start.sh`
- `start.sh`: Launches `builds/server/SentinelServer.x86_64`
- `railway.json`: NIXPACKS builder config
- Bootstrap.gd reads `$PORT` env var

**Server**: web-production-5b732.up.railway.app:443

## Testing

**Local Testing**:
```bash
# Single client (auto-connect to localhost)
run_client_local.bat

# Full test session (1 server + 3 clients, auto-connect, quadrant layout)
start_test_session.bat

# Stop all
stop_test_session.bat
```

**Flags**:
- `--server` - Run as server
- `--client` - Run as client
- `--auto-connect` - Skip connection UI, connect immediately
- `--host=X` - Server hostname
- `--port=Y` - Server port

## Design Goals (TODO.md)

**Phase 1 - Feel Good** (Quick Wins):
- Muzzle flash + shooting sound
- Screen shake on damage
- Health bar always visible
- Minimap
- Kill feed

**Phase 2 - Core Loop**:
- Loot drops from enemies
- Pickup/inventory system
- Resource gathering
- World events (timed loot spawns)

**Phase 3 - Anti-Bullying**:
- Hot loot (AI aggro, map visibility, can't store)
- Bounty system (kill low-level = bounty)
- Lawfulness zones (Safe/Neutral/Lawless)
- Robin Hood mechanics (raid rich = good loot)

**Phase 4 - Progression**:
- Player levels + XP
- Equipment tiers
- Base building expansion
- Crafting system

## Code Patterns

**Entity Spawn (Server)**:
```gdscript
var entity = EntityType.new()
entity.net_id = Replication.generate_id()
entity.authority = 1
_world.add_child(entity)
Net.spawn_entity.rpc({"type": "...", "net_id": id, "pos": pos})
```

**Client Prediction**:
```gdscript
var cmd = {"seq": _seq, "mv": mv, "aim": aim, "btn": btn}
Net.server_receive_input.rpc_id(1, cmd)
entity.apply_input(mv, aim, btn, dt)
_pending_inputs.append(cmd)
_predicted_states[_seq] = entity.get_replicated_state()
```

**Interpolation**:
```gdscript
var render_tick = _latest_tick - INTERP_DELAY_TICKS
var t = (render_tick - ta) / (tb - ta)
entity.position = sa["p"].lerp(sb["p"], t)
```

**State Replication**:
```gdscript
// Player.gd
func get_replicated_state() -> Dictionary:
	return {"p": position, "r": rotation, "h": health, "v": velocity}

func apply_replicated_state(state: Dictionary) -> void:
	# Detect health decrease
	var new_health = state.get("h", health)
	if new_health < health:
		_hurt_flash_timer = 0.2
	health = new_health
```

## Recent Changes

**Wall Optimization** (Current Session):
- Walls no longer interpolated (static entities)
- Only health updates from snapshots
- Performance: 30-50% fewer entities in interpolation loop
- Position reconciliation only checks position (not health)
- Health applied immediately from snapshots for local player

**Visual Polish**:
- Hurt flash effect (red flash on damage)
- Local player color = black (easy identification)
- Reconciliation checks position only (health from snapshots)

**Testing QoL**:
- `--auto-connect` flag
- `run_client_local.bat` for quick localhost testing
- Auto-connect in test session

**Deployment**:
- Live on itch.io
- Server running 24/7 on Railway

## Known Issues
None currently

## Next Session
Start with Quick Wins from TODO.md:
- Muzzle flash
- Shooting sound
- Screen shake
- Health bar improvements
- Kill feed
