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
├── systems/Log.gd            # Logging system (autoload)
├── Bootstrap.gd              # Entry (--server/--client)
├── client/ClientMain.gd      # Prediction + interpolation
├── server/ServerMain.gd      # Authoritative simulation
├── entities/
│   ├── Player.gd            # Networked player (dash mechanic)
│   ├── Enemy.gd             # AI enemy (aggro system)
│   ├── Bullet.gd            # Client-predicted projectile
│   └── Wall.gd              # Buildable structure
├── shared/
│   ├── NetworkedEntity.gd   # Base replicated entity
│   ├── ReplicationManager.gd # Entity registry
│   └── GameConstants.gd     # Shared constants
└── net/Net.gd               # Dual protocol transport
```

### Logging System
```gdscript
// Log.gd (autoload)
enum Category { NETWORK, ENTITY, SNAPSHOT, INPUT, RECONCILE, ... }

// Usage
Log.network("Connected to server")
Log.entity("Spawned player %d" % id)
Log.warn("Missing entity")

// Categories disabled by default: SNAPSHOT, INPUT, PHYSICS (spammy)
// Runtime control: Log.set_verbose(true)
```

### Network Diagnostics
```gdscript
// ClientMain.gd - F3 toggle
var _debug_visible: bool = false  // Press F3
var _debug_label: Label           // Top-right overlay

// Metrics tracked:
- FPS (60-sample average)
- Tick interval (server snapshot rate)
- Ping (round-trip on every 10th input)
- Snapshot delivery % (loss calculation)
- Reconciles/sec
- Entity counts (total + interpolated)
- Pending input buffer size
```

### Static Entity Resync
```gdscript
// ServerMain.gd
const STATIC_SNAPSHOT_INTERVAL: 5.0

func _send_static_snapshot():
	var static_states = {}
	for wall in _walls:
		static_states[str(wall.net_id)] = {
			"pos": wall.position, "health": wall.health
		}
	Net.client_receive_static_snapshot.rpc(static_states)

// ClientMain.gd - spawns missing walls, updates health
func _on_static_snapshot(states: Dictionary):
	for net_id in states:
		var wall = Replication.get_entity(net_id)
		if not wall: spawn_wall(state)  // Missing → create
		else: wall.health = state["health"]  // Exists → sync
```

### Enemy Aggro System
```gdscript
// Enemy.gd
var _damage_taken: Dictionary = {}  // player_id -> damage
var _aggro_target: Player = null
var _aggro_lock_time: float = 0.0

const ENEMY_AGGRO_RANGE: 600.0
const ENEMY_AGGRO_LOCK_TIME: 3.0

func take_damage(amount, attacker_id):
	_damage_taken[attacker_id] += amount
	_aggro_target = get_player(attacker_id)
	_aggro_lock_time = 3.0
	
	// Immediately interrupt wander/separate
	if _state != CHASE:
		_state = CHASE
		_state_timer = randf_range(8, 12)

func _get_aggro_target():
	// Keep locked if valid + in range
	if _aggro_lock_time > 0 and _aggro_target:
		return _aggro_target
	
	// Find top damage dealer
	return get_player_with_most_damage() or _find_nearest_player()
```

### Dash Mechanic
```gdscript
// GameConstants.gd
const PLAYER_DASH_SPEED: 600.0      // 2.7x normal
const PLAYER_DASH_DURATION: 0.15    // Short burst
const PLAYER_DASH_COOLDOWN: 2.0
const BTN_DASH: 4

// Player.gd
var _dash_timer: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector2

func apply_input(mv, aim, buttons, dt):
	// Activate dash
	if buttons & BTN_DASH and _dash_cooldown <= 0 and mv.length() > 0:
		_dash_timer = DASH_DURATION
		_dash_cooldown = DASH_COOLDOWN
		_dash_direction = mv.normalized()
	
	// Apply velocity
	if _dash_timer > 0:
		velocity = _dash_direction * DASH_SPEED
	else:
		velocity = mv * MOVE_SPEED

// ClientMain.gd - spacebar mapped to ui_dash
if Input.is_action_pressed("ui_dash"):
	btn |= GameConstants.BTN_DASH

// TODO: Change to is_action_just_pressed (prevent hold spam)
```

## Networking Model
**Server**: Authoritative, 60 FPS fixed timestep  
**Client**: Prediction (local player) + Interpolation (remote entities)

**Input Flow**:
1. Client samples input → sends to server
2. Client predicts locally (instant response)
3. Server simulates → sends snapshot
4. Client reconciles if misprediction

**Entity Handling**:
- Players: Predict own, interpolate others
- Enemies: Server-authoritative, interpolate
- Bullets: Client-predicted spawn, client collision
- Walls: Static (health-only updates, no interpolation)

## Constants (GameConstants.gd)
```gdscript
PHYSICS_FPS: 60
PLAYER_MOVE_SPEED: 220.0
PLAYER_DASH_SPEED: 600.0
ENEMY_AGGRO_RANGE: 600.0
ENEMY_AGGRO_LOCK_TIME: 3.0
INTERP_DELAY_TICKS: 2
RECONCILE_POSITION_THRESHOLD: 5.0
```

## Testing
```bash
start_test_session.bat  # 1 server + 3 clients
run_client_local.bat     # Single client → localhost
```

## Recent Changes

**Session #2 - Logging, Static Sync, Enemy Aggro, Dash**:
- Network diagnostics UI (F3 toggle)
- Centralized logging system
- Static wall resync (5s snapshots)
- Enemy aggro (damage-based, 3s lock)
- Dash mechanic (spacebar, 600 speed)
- Bug fix: Silent despawn for missing entities

**Session #1 - Network Optimization & Hurt Flash**:
- Wall optimization (static, no interpolation)
- Position-only reconciliation
- Hurt flash for enemies

## Known Issues
- Dash uses `is_action_pressed` instead of `is_action_just_pressed` (sends spam while held)

## Next Session
- Fix dash input (just_pressed)
- Muzzle flash + shooting sound
- Screen shake on damage
- Health bar improvements
