# Session Summary 2 - Logging, Static Sync, Enemy Aggro, Dash Mechanic

**Date:** 2026-01-11  
**Focus:** Network diagnostics, logging system, wall resync, enemy AI improvements, dash movement

---

## Completed Features

### 1. Network Diagnostics UI (F3 Toggle)
**Location:** `ClientMain.gd`

```gdscript
# Debug overlay - top-right, F3 to toggle
var _debug_visible: bool = false
var _debug_label: Label
var _ping_ms: float = 0.0
var _snapshot_count: int = 0
var _reconcile_count: int = 0

# Display metrics
text += "FPS: %d\n" % int(avg_fps)
text += "Tick: %d ms\n" % int(avg_sps)
text += "Ping: %d ms\n" % int(_ping_ms)
text += "Snapshots: %d/%d (%.1f%% loss)\n" % [count, expected, loss]
text += "Reconciles/sec: %d\n" % _reconcile_count
```

**Metrics tracked:**
- Client FPS
- Server tick interval
- Round-trip ping
- Snapshot delivery rate
- Reconciliation frequency
- Entity counts
- Pending input buffer size

---

### 2. Centralized Logging System
**Location:** `scripts/systems/Log.gd` (autoload singleton)

```gdscript
# Categories with enable/disable
enum Category {
    NETWORK,      # Enabled - connections, disconnects
    ENTITY,       # Enabled - spawn/despawn
    SNAPSHOT,     # Disabled - very spammy (60/sec)
    INPUT,        # Disabled - very spammy (60/sec)
    RECONCILE,    # Enabled - reconciliation events
    PHYSICS,      # Disabled - physics simulation
    DEBUG,        # Enabled - general debug
    WARNING,      # Enabled - warnings
    ERROR,        # Enabled - always shown
}

# Usage
Log.network("Connected to server")
Log.entity("Spawned player %d" % peer_id)
Log.warn("Missing entity %d" % net_id)

# Runtime control
Log.set_verbose(true)  # Enable snapshot/input/physics
Log.enable(Log.Category.SNAPSHOT)
```

**Migrated all print statements** in ClientMain, ServerMain, Net to use logging system.

---

### 3. Static Entity Resync
**Problem:** Walls could desync due to dropped spawn RPCs or late-joining clients.

**Solution:** Dual approach
1. **Reliable wall spawns** - per-client RPC instead of broadcast
2. **Static snapshot** - full wall state every 5 seconds (reliable)

**ServerMain.gd:**
```gdscript
const STATIC_SNAPSHOT_INTERVAL: float = 5.0
var _static_snapshot_timer: float = 0.0

func _send_static_snapshot() -> void:
    var static_states = {}
    for wall in _walls:
        static_states[str(wall.net_id)] = {
            "type": "wall",
            "pos": wall.global_position,
            "health": wall.health,
            "builder": wall.builder_id
        }
    Net.client_receive_static_snapshot.rpc(static_states)
```

**ClientMain.gd:**
```gdscript
func _on_static_snapshot(states: Dictionary) -> void:
    for net_id_str in states:
        var wall = Replication.get_entity(net_id)
        if not wall:
            # Spawn missing wall
            wall = Wall.new()
            wall.net_id = net_id
            wall.global_position = state["pos"]
            wall.health = state["health"]
            _world.add_child(wall)
        else:
            # Update health
            wall.health = state["health"]
```

---

### 4. Enemy Aggro System
**Problem:** Enemies used simple nearest-player targeting.

**Solution:** Damage-based aggro with sticky targeting.

**Enemy.gd:**
```gdscript
# Aggro tracking
var _damage_taken: Dictionary = {}  # player_id -> damage_dealt
var _aggro_target: Player = null
var _aggro_lock_time: float = 0.0

const ENEMY_AGGRO_RANGE: float = 600.0
const ENEMY_AGGRO_LOCK_TIME: float = 3.0

func take_damage(amount: float, attacker_id: int = 0) -> bool:
    health -= amount
    
    if attacker_id > 0:
        # Track damage
        _damage_taken[attacker_id] = _damage_taken.get(attacker_id, 0.0) + amount
        
        # Lock aggro to attacker
        _aggro_target = get_player(attacker_id)
        _aggro_lock_time = 3.0
        
        # Immediately switch to CHASE state
        if _state != State.CHASE:
            _state = State.CHASE
            _state_timer = randf_range(8.0, 12.0)
    
    return health <= 0

func _get_aggro_target() -> Player:
    # Keep locked target if valid
    if _aggro_lock_time > 0.0 and _aggro_target:
        if distance_to(_aggro_target) < ENEMY_AGGRO_RANGE:
            return _aggro_target
    
    # Find player who dealt most damage
    var top_damage = 0.0
    var top_attacker: Player = null
    for player_id in _damage_taken:
        if _damage_taken[player_id] > top_damage:
            top_attacker = get_player(player_id)
    
    return top_attacker if top_attacker else _find_nearest_player()
```

**Bullet.gd:**
```gdscript
# Pass attacker ID to enemy
func _on_hit_enemy(enemy: Enemy) -> void:
    if Net.is_server():
        enemy.take_damage(GameConstants.BULLET_DAMAGE, owner_id)
```

**Behavior:**
- Enemy tracks damage per player
- Locks to attacker for 3 seconds
- After lock expires, targets highest damage dealer
- Drops aggro beyond 600 units
- Instantly interrupts wander/separate on damage

---

### 5. Dash Mechanic (Spacebar)
**Location:** `Player.gd`, `ClientMain.gd`

**Constants:**
```gdscript
const PLAYER_DASH_SPEED: float = 600.0    # 2.7x normal speed
const PLAYER_DASH_DURATION: float = 0.15  # Short burst
const PLAYER_DASH_COOLDOWN: float = 2.0   # Between dashes
const BTN_DASH: int = 4
```

**Player.gd:**
```gdscript
var _dash_timer: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO

func apply_input(mv: Vector2, aim: Vector2, buttons: int, dt: float):
    # Activate dash
    if buttons & BTN_DASH and _dash_cooldown <= 0.0 and mv.length() > 0.01:
        _dash_timer = GameConstants.PLAYER_DASH_DURATION
        _dash_cooldown = GameConstants.PLAYER_DASH_COOLDOWN
        _dash_direction = mv.normalized()
    
    # Apply velocity (dash overrides normal)
    if _dash_timer > 0.0:
        velocity = _dash_direction * GameConstants.PLAYER_DASH_SPEED
    else:
        velocity = mv * GameConstants.PLAYER_MOVE_SPEED
```

**Input mapping:**
```gdscript
# project.godot
ui_dash={
"events": [InputEventKey, physical_keycode=32]  # Spacebar
}

# ClientMain.gd
if Input.is_action_pressed("ui_dash"):
    btn |= GameConstants.BTN_DASH
```

**Known Issue:** Uses `is_action_pressed` (hold) instead of `is_action_just_pressed` (tap). Should fix to prevent spam.

---

## Bug Fixes

### Bullet Despawn Warning
**Problem:** `[WARN] Entity 10018 not found in Replication`

**Cause:** Enemy bullets despawn before spawn RPC arrives (short-lived entities).

**Fix:** Silently ignore missing entities in despawn RPC.
```gdscript
func despawn_entity(net_id: int) -> void:
    var entity = Replication.get_entity(net_id)
    if entity:
        Log.entity("Despawning entity %d" % net_id)
        entity.queue_free()
    # Silently ignore if not found - likely short-lived bullet
```

---

## Next Session TODO

### High Priority
- [ ] **Fix dash input** - Change to `is_action_just_pressed` to prevent hold spam
- [ ] Muzzle flash + shooting sound
- [ ] Screen shake on damage
- [ ] Health bar always visible
- [ ] Kill feed

### Backlog
- [ ] Dash particles/trail effect
- [ ] Dash cooldown UI indicator
- [ ] Minimap
- [ ] Simple loot drops from enemies

---

## Files Modified

**Core Systems:**
- `scripts/systems/Log.gd` (new)
- `scripts/shared/GameConstants.gd`
- `project.godot`

**Networking:**
- `scripts/net/Net.gd`
- `scripts/client/ClientMain.gd`
- `scripts/server/ServerMain.gd`

**Entities:**
- `scripts/entities/Player.gd`
- `scripts/entities/Enemy.gd`
- `scripts/entities/Bullet.gd`

**Config:**
- `TODO.md`
