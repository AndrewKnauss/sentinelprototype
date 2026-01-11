# CLAUDE.md - Persistent Context

## Project Overview
**Sentinel Prototype** - Top-down 2D multiplayer survival (Rust-like progression)  
Humans vs machines + PvP/raiding, scavenging sandbox

## Tech Stack
- **Engine**: Godot 4.4.1
- **Language**: GDScript
- **Networking**: WebSocket (default) / ENet (toggle)
- **Hosting**: Railway.app (web-production-5b732.up.railway.app:443)
- **Resolution**: 1920x1080 fullscreen

## Architecture

### Core Files
```
scripts/
├── Bootstrap.gd              # Entry (--server/--client, reads Railway PORT)
├── client/ClientMain.gd      # Prediction + interpolation + connection UI
├── server/ServerMain.gd      # Authoritative simulation
├── entities/
│   ├── Player.gd            # Networked player
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
4. Client reconciles if misprediction

**Entity Types**:
- Players: Client predicts own, interpolates others
- Enemies: Server-authoritative, client interpolates
- Bullets: Client-predicted spawn, client collision, server validates damage
- Walls: Server-authoritative, client interpolates

### Key Systems

**Prediction/Reconciliation**:
```gdscript
_input_seq: int
_pending_inputs: Array
_predicted_states: Dictionary
```

**Interpolation**:
```gdscript
_snap_buffers: Dictionary  // net_id -> [{tick, state}]
INTERP_DELAY_TICKS: 2
```

**Bullet Handling**:
- Client spawns instantly (net_id=-1, authority=client_id)
- Server spawns authoritative (sends RPC)
- Client skips if owner matches
- Collision runs both sides (visual + authoritative)

**Connection UI** (ClientMain.gd):
```gdscript
// Host/port inputs + Connect button
// Defaults: web-production-5b732.up.railway.app:443
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
**Local**: `start_test_session.bat` (1 server + 3 clients, quadrant layout)  
**Cloud**: Client connects via UI to Railway server

## Design Goals
- World events (timed loot spawns)
- Anti-bullying (hot loot, bounties)
- Lawfulness zones (PvP consequences vary)
- Resource gathering + crafting

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
```

**Interpolation**:
```gdscript
var render_tick = _latest_tick - INTERP_DELAY_TICKS
var t = (render_tick - ta) / (tb - ta)
entity.position = sa["p"].lerp(sb["p"], t)
```

## Recent Changes
- WebSocket implementation (browser support)
- Railway deployment (cloud server)
- Connection UI (no auto-connect)
- WSS support for HTTPS

## Next
- HTML5 export → itch.io
- World events system
- Inventory/loot
