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
│   ├── Player.gd            # Networked player (dash, sprint, weapons)
│   ├── Enemy.gd             # AI enemy (aggro system)
│   ├── Bullet.gd            # Client-predicted projectile
│   └── Wall.gd              # Buildable structure
├── components/
│   └── Weapon.gd            # Weapon component (ammo, reload)
├── shared/
│   ├── NetworkedEntity.gd   # Base replicated entity
│   ├── ReplicationManager.gd # Entity registry
│   ├── GameConstants.gd     # Shared constants
│   └── WeaponData.gd        # Weapon definitions
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
PLAYER_DASH_SPEED: 1000.0
PLAYER_SPRINT_SPEED: 330.0
PLAYER_STAMINA_MAX: 100.0
PLAYER_STAMINA_COST: 20.0 (per sec)
PLAYER_STAMINA_REGEN: 15.0 (per sec)
ENEMY_AGGRO_RANGE: 600.0
ENEMY_AGGRO_LOCK_TIME: 3.0
INTERP_DELAY_TICKS: 2
RECONCILE_POSITION_THRESHOLD: 5.0
BTN_SHOOT: 1
BTN_BUILD: 2
BTN_DASH: 4
BTN_SPRINT: 8
```

## Testing
```bash
start_test_session.bat  # 1 server + 3 clients
run_client_local.bat     # Single client → localhost
```

## Recent Changes

**Session #5 - Collision System + Component Pattern Refactor**:
- **MAJOR ARCHITECTURAL REFACTOR**: Complete rewrite to component-based networking
  - `NetworkedEntity` is now a **RefCounted component** (was Node2D base class)
  - Entities extend their proper physics body types:
    - `Player` extends `CharacterBody2D`
    - `Enemy` extends `CharacterBody2D`
    - `Wall` extends `StaticBody2D`
    - `Bullet` extends `Node2D` (uses raycasting)
  - Each entity holds a `net_entity: NetworkedEntity` component for replication
  - `ReplicationManager` stores components, returns owner nodes
  - Movement uses native `move_and_slide()` - **NO MORE POSITION SYNCING**
  - Cleaner separation: physics ownership vs networking concerns
- **Collision System (Phase 1)** - Walls block movement
  - Collision layers properly configured:
    - Layer 1 (STATIC): Walls and structures
    - Layer 2 (PLAYER): Player characters
    - Layer 3 (ENEMY): AI enemies (bit value 4)
    - Layer 4 (PROJECTILE): Bullets (raycast-based)
  - Wall sliding behavior (smooth movement along walls)
  - Phase-through behavior (players/enemies don't collide with each other)
  - **Bug fix**: Eliminated teleporting/circular movement caused by position feedback loops
- Design doc: `docs/systems/COLLISION.md` (covers future FOG, sound, interaction)
- **Benefits**: Simpler code, no teleporting, Godot-idiomatic, type-safe, future-proof

**Session #4 - Database Persistence + Username System**:
- **Username-based identity** (solves peer_id persistence problem)
  - Usernames persist across sessions (peer_ids don't)
  - Client sends username on connect
  - Server validates (3-16 chars, alphanumeric + underscore)
  - Username uniqueness enforced (one session per username)
  - Case-insensitive storage ("Alice" = "alice")
- **Username validation** (`UsernameValidator.gd`)
  - Client-side + server-side validation
  - Reserved names list (admin, server, moderator, system, bot)
  - Regex enforcement (alphanumeric + underscore only)
- **Username input UI** (`UsernameDialog.gd`)
  - Shows after connection if --username not provided
  - Live validation feedback
  - Server response handling (success/error)
- **Command-line username support**
  - `run_client_local.bat Alice` → auto-login as Alice
  - `--username=Alice` flag for auto-connect
  - `start_test_session.bat` uses Alice/Bob/Charlie
- **Persistence abstraction layer** (swappable backends)
- **JSON persistence backend** (zero dependencies, human-readable)
- **Player login system** (load on connect, save on disconnect)
- **Structure persistence** (walls survive server restart)
- **30-second autosave** (all players + structures)
- **Admin commands** (F5=wipe structures, F6=wipe players, F7=show stats)
- **Graceful shutdown** (saves all data on server close)
- File structure:
  - `user://saves/players/{username}.json` - One file per player (by username)
  - `user://saves/inventory/{username}.json` - One file per inventory (TODO)
  - `user://saves/structures.json` - All structures (owner_username field)
- Player data saved: username, position, health (level/xp/currency ready)
- Structure data saved: type, position, health, owner_username
- Ready for SQLite migration when >50 concurrent players

**Session #3 - Sprint, Weapons & Enemy Variety**:
- Sprint mechanic (Shift key, 330 speed = 1.5x base)
- Stamina system (100 max, drains 20/sec, regens 15/sec)
- Stamina bar UI (yellow, below health, hides when full)
- **Weapon system** (5 types: Pistol, Rifle, Shotgun, Sniper, SMG)
- Weapon data (damage, fire rate, spread, pellets)
- Ammo & reload mechanics (R key)
- Weapon switching (1/2/3 keys)
- Multi-pellet shotgun
- Ammo HUD display (bottom-right)
- Network sync for weapon state
- Players start with Pistol/Rifle/Shotgun for testing
- **Enemy variety** (5 types: Scout, Tank, Sniper, Swarm, Normal)
  - Scout: Fast, fragile, kites at range (140 speed, 80 hp, 15 dmg)
  - Tank: Slow, armored, charges (50 speed, 400 hp, 35 dmg, 60% armor)
  - Sniper: Long range with laser warning (700 range, 60 dmg, 1.5s aim time)
  - Swarm: Fast, weak, aggressive (120 speed, 50 hp, 10 dmg)
  - Normal: Balanced baseline (80 speed, 150 hp, 25 dmg)
- Weighted random spawning (25% Scout, 25% Swarm, 15% Tank/Sniper, 20% Normal)
- Enemy type synced to clients
- Color-coded sprites (Orange=Scout, Gray=Tank, Purple=Sniper, Cyan=Swarm)

**Session #2 - Logging, Static Sync, Enemy Aggro, Dash**:
- Network diagnostics UI (F3 toggle)
- Centralized logging system
- Static wall resync (5s snapshots)
- Enemy aggro (damage-based, 3s lock)
- Dash mechanic (spacebar, 1000 speed)
- Bug fix: Silent despawn for missing entities

**Session #1 - Network Optimization & Hurt Flash**:
- Wall optimization (static, no interpolation)
- Position-only reconciliation
- Hurt flash for enemies

## Known Issues
- None currently

## Next Session
- **Session 6: Loot & Inventory System**
- Item definitions (ItemData)
- ItemDrop entity (spawns on ground)
- Inventory component (20 slots)
- E-key pickup interaction
- Drop on death
- Inventory UI (grid display)
- Polish pass when combat feels good (muzzle flash, sounds, particles)
