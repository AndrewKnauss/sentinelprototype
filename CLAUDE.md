# CLAUDE.md - Persistent Context

## Project Overview
**Sentinel Prototype** - Indie-scope top-down 2D multiplayer survival game  
Rust-like progression, scavenging sandbox, humans vs machines + PvP/raiding

## Tech Stack
- **Engine**: Godot 4.4.1
- **Language**: GDScript
- **Networking**: ENet (client-server, authoritative server)
- **Resolution**: 1920x1080 (fullscreen, canvas_items stretch)

## Architecture

### File Structure
```
scripts/
├── Bootstrap.gd              # Entrypoint (--server/--client args)
├── client/ClientMain.gd      # Client controller (prediction + interpolation)
├── server/ServerMain.gd      # Server controller (authoritative simulation)
├── entities/
│   ├── Player.gd            # Networked player
│   ├── Enemy.gd             # AI enemy
│   ├── Bullet.gd            # Client-predicted projectile
│   └── Wall.gd              # Buildable structure
├── shared/
│   ├── NetworkedEntity.gd   # Base class for replicated entities
│   ├── ReplicationManager.gd # Entity registry autoload
│   └── GameConstants.gd     # Shared constants
└── net/Net.gd               # Network transport autoload
```

### Networking Model
**Server**: Authoritative, runs at 60 FPS fixed timestep  
**Client**: Prediction (local player) + Interpolation (remote entities)

**Input Flow**:
1. Client samples input → sends to server
2. Client predicts movement locally (instant response)
3. Server receives input → simulates → sends snapshot
4. Client reconciles prediction vs server state

**Entity Replication**:
- Players: Client predicts own, interpolates others
- Enemies: Server-authoritative, client interpolates
- Bullets: Client-predicted spawns, client collision, server validates damage
- Walls: Server-authoritative, client interpolates

### Key Systems

**Prediction/Reconciliation** (ClientMain.gd):
```gdscript
_input_seq: int                    # Input sequence number
_pending_inputs: Array             # Unconfirmed inputs
_predicted_states: Dictionary      # States for each seq
```

**Interpolation** (ClientMain.gd):
```gdscript
_snap_buffers: Dictionary          # net_id -> Array[{tick, state}]
INTERP_DELAY_TICKS: 2             # Render 2 ticks behind
```

**Bullet Handling**:
- Client spawns instantly (net_id = -1, authority = client_id)
- Server spawns authoritative version (sends RPC)
- Client skips server spawn if owner matches local player
- Collision runs on both client (visual) and server (authoritative)

## Constants (GameConstants.gd)
```gdscript
PHYSICS_FPS: 60
PLAYER_MOVE_SPEED: 220.0
ENEMY_MOVE_SPEED: 80.0
BULLET_SPEED: 800.0
BULLET_DAMAGE: 25.0
INTERP_DELAY_TICKS: 2
RECONCILE_POSITION_THRESHOLD: 5.0
```

## Testing
**Scripts**: `start_test_session.bat` / `stop_test_session.bat`  
**Layout**: 1 server (top-left) + 3 clients (top-right, bottom-left, bottom-right)

## Design Goals (Future)
- **World Events**: Timed loot spawns for contested PvP
- **Anti-Bullying**: Hot loot (AI aggro), bounties, Robin Hood incentives
- **Lawfulness Zones**: PvP consequences vary by map zone
- **Progression**: Resource gathering, crafting, base building

## Code Style
- Clear section comments with `# ===...===`
- Docstrings for public functions: `"""Purpose."""`
- Type hints: `func foo(x: int) -> bool:`
- Naming: `_private_var`, `public_var`, `CONSTANT`

## Common Patterns

**Entity Spawning (Server)**:
```gdscript
var entity = EntityType.new()
entity.net_id = Replication.generate_id()
entity.authority = 1  # Server
_world.add_child(entity)
Net.spawn_entity.rpc({"type": "typename", "net_id": id, "pos": pos, "extra": {}})
```

**Client-Side Prediction**:
```gdscript
# Sample input
var cmd = {"seq": _seq, "mv": mv, "aim": aim, "btn": btn}
Net.server_receive_input.rpc_id(1, cmd)

# Predict locally
entity.apply_input(mv, aim, btn, dt)
_pending_inputs.append(cmd)
_predicted_states[_seq] = entity.get_replicated_state()
```

**Interpolation**:
```gdscript
var render_tick = _latest_tick - INTERP_DELAY_TICKS
var buf = _snap_buffers[net_id]
# Find snapshots at render_tick
var t = (render_tick - ta) / (tb - ta)
entity.position = sa["p"].lerp(sb["p"], t)
```

## Recent Changes
- Added client-side bullet prediction (zero-latency shooting)
- Moved collision detection into Bullet.gd (runs on client + server)
- Added camera following with smoothing
- Configured fullscreen scaling
- Created quadrant test session launcher

## Known Issues
None currently

## Notes
- Bullets don't reconcile (acceptable - fast, short-lived, visual feedback > perfect sync)
- Server always authoritative for damage/kills
- Client collision is optimistic (instant feedback)
