# Enemy Types & Sprint System

## Sprint Mechanics

### Player Sprint
```gdscript
# shared/GameConstants.gd
const PLAYER_SPRINT_SPEED: float = 330.0  # 1.5x base (220)
const PLAYER_SPRINT_STAMINA_COST: float = 20.0  # Per second
const PLAYER_STAMINA_MAX: float = 100.0
const PLAYER_STAMINA_REGEN: float = 15.0  # Per second when not sprinting
const BTN_SPRINT: int = 8

# entities/Player.gd
var stamina: float = GameConstants.PLAYER_STAMINA_MAX
var is_sprinting: bool = false

func apply_input(mv: Vector2, aim: Vector2, buttons: int, dt: float):
	# Sprint check
	var wants_sprint = (buttons & GameConstants.BTN_SPRINT) and mv.length() > 0.1
	
	if wants_sprint and stamina > 0:
		is_sprinting = true
		stamina -= GameConstants.PLAYER_SPRINT_STAMINA_COST * dt
		if stamina < 0:
			stamina = 0
	else:
		is_sprinting = false
		stamina += GameConstants.PLAYER_STAMINA_REGEN * dt
		if stamina > GameConstants.PLAYER_STAMINA_MAX:
			stamina = GameConstants.PLAYER_STAMINA_MAX
	
	# Apply movement (sprint overrides dash)
	if _dash_timer > 0.0:
		velocity = _dash_direction * GameConstants.PLAYER_DASH_SPEED
	elif is_sprinting:
		velocity = mv * GameConstants.PLAYER_SPRINT_SPEED
	else:
		velocity = mv * GameConstants.PLAYER_MOVE_SPEED
	
	# ... rest of apply_input

# Stamina bar UI
func _update_stamina_bar():
	var pct = stamina / GameConstants.PLAYER_STAMINA_MAX
	_stamina_bar.size.x = 20 * pct
	_stamina_bar.visible = pct < 1.0  # Hide when full
```

### Client Input
```gdscript
# ClientMain.gd
func _send_and_predict(dt: float):
	# ... existing input sampling
	
	if Input.is_key_pressed(KEY_SHIFT):
		btn |= GameConstants.BTN_SPRINT
```

---

## Implementation Notes (Session 3)

### Completed Features
- [x] Scout: Kiting AI with strafing
- [x] Tank: Armor (60% reduction) + charge ability
- [x] Sniper: Laser sight warning (1.5s) + long range
- [x] Swarm: Simplified rush (no pack coordination)
- [x] Normal: Baseline enemy

### Critical Fixes Applied

**Color Modulation Issue**:
- Problem: Enemy texture was RED, causing incorrect color multiplication
- Fix: Changed texture from `Color.RED` to `Color.WHITE` in Enemy.gd
- Child classes must set `_base_color` BEFORE calling `super._ready()`

**Sniper Laser Client Visibility**:
- Problem: `_is_aiming` state not applied during interpolation
- Fix: Added `entity.apply_replicated_state(sb)` in ClientMain's `_interpolate_entity()`
- Laser now uses local coordinates (`Vector2.RIGHT * dist`) since Line2D rotates with parent

**Network Sync**:
- Enemy types sent via `extra.enemy_type` in spawn_entity RPC
- Types preserved on respawn (server tracks type and respawns same)
- Client spawns correct class based on type string

### Spawn Weights
```gdscript
types = ["scout", "tank", "sniper", "swarm", "normal"]
weights = [0.25, 0.15, 0.15, 0.25, 0.2]
```
- Scout/Swarm: 50% (action-focused)
- Tank/Sniper: 30% (variety)
- Normal: 20% (baseline)

### Balance Observations
- Sniper 1.5s aim time feels good (visible warning)
- Tank charge (8s cooldown, 2s duration) creates interesting chase dynamics
- Scout kiting at 300-500 range works well
- Swarm simplified from original design (no pack coordination needed)

### Healer Deferred
Original design included Healer enemy type but was cut for complexity:
- Would require AOE heal detection
- Needs visual effects for healing
- Adds significant AI coordination overhead
- Can be added later if needed

### Files Modified
- `scripts/entities/Enemy.gd` - Added `_base_color` variable, changed texture to WHITE
- `scripts/entities/enemies/EnemyScout.gd` - Kiting AI
- `scripts/entities/enemies/EnemyTank.gd` - Armor + charge
- `scripts/entities/enemies/EnemySniper.gd` - Laser sight + aim delay
- `scripts/entities/enemies/EnemySwarm.gd` - Simplified rush
- `scripts/server/ServerMain.gd` - Weighted spawn system, type preservation
- `scripts/net/Net.gd` - Enemy type in spawn RPC
- `scripts/client/ClientMain.gd` - Apply full replicated state for enemies

### Testing Verified
- [x] All enemy types spawn with correct colors
- [x] Scout kites and strafes
- [x] Tank charges when in range (100-400)
- [x] Sniper laser visible to all clients
- [x] Swarm rushes aggressively
- [x] Different damage values apply correctly
- [x] Enemies respawn as same type
- [x] Late-joining clients see correct types

---

## Enemy Types

### 1. Scout (Fast, Fragile)
**Role**: Early warning, harassment, kiting  
**Behavior**: Maintains distance, shoots while retreating

```gdscript
# entities/EnemyScout.gd
extends Enemy
class_name EnemyScout

const SCOUT_SPEED = 140.0  # 1.75x normal (80)
const SCOUT_HEALTH = 80.0  # 0.53x normal (150)
const SCOUT_DAMAGE = 15.0  # 0.6x normal (25)
const SCOUT_RANGE = 500.0  # Longer range
const SCOUT_KITE_DISTANCE = 300.0  # Preferred distance

func _ai_chase_and_shoot(delta: float):
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	rotation = to_player.angle()
	
	# Kite behavior: back away if too close
	if dist < SCOUT_KITE_DISTANCE:
		velocity = -to_player.normalized() * SCOUT_SPEED
	elif dist > SCOUT_RANGE:
		velocity = to_player.normalized() * SCOUT_SPEED
	else:
		velocity = Vector2.ZERO  # Stay at preferred range
	
	global_position += velocity * delta
	
	# Shoot frequently
	if dist < SCOUT_RANGE and _shoot_cooldown <= 0:
		_shoot_cooldown = 1.2  # Fast fire rate
		wants_to_shoot.emit(to_player.normalized())
```

### 2. Tank (Slow, High HP)
**Role**: Absorb damage, protect other enemies  
**Behavior**: Charges players, bodyblocks

```gdscript
# entities/EnemyTank.gd
extends Enemy
class_name EnemyTank

const TANK_SPEED = 50.0  # 0.625x normal
const TANK_HEALTH = 400.0  # 2.67x normal
const TANK_DAMAGE = 35.0  # 1.4x normal
const TANK_ARMOR = 0.5  # Takes 50% damage

var is_charging: bool = false
var charge_cooldown: float = 0.0

func take_damage(amount: float, attacker_id: int = 0) -> bool:
	# Apply armor reduction
	amount *= TANK_ARMOR
	return super.take_damage(amount, attacker_id)

func _ai_chase_and_shoot(delta: float):
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	rotation = to_player.angle()
	
	# Charge ability (every 10 seconds)
	if charge_cooldown <= 0 and dist > 100 and dist < 400:
		is_charging = true
		charge_cooldown = 10.0
	
	if is_charging:
		velocity = to_player.normalized() * (TANK_SPEED * 3.0)  # 150 during charge
		
		# End charge after 2 seconds
		if charge_cooldown > 8.0:
			is_charging = false
	else:
		velocity = to_player.normalized() * TANK_SPEED
		charge_cooldown -= delta
	
	global_position += velocity * delta
	
	# Melee preference
	if dist < 50:
		wants_to_shoot.emit(to_player.normalized())
		_shoot_cooldown = 0.5  # Melee attack
```

### 3. Sniper (Long Range, Stationary)
**Role**: Area denial, punish stationary targets  
**Behavior**: Finds cover, laser sight warning

```gdscript
# entities/EnemySniper.gd
extends Enemy
class_name EnemySniper

const SNIPER_SPEED = 60.0  # Slow repositioning
const SNIPER_HEALTH = 100.0  # Fragile
const SNIPER_DAMAGE = 60.0  # 2.4x normal - high burst
const SNIPER_RANGE = 800.0  # Very long
const SNIPER_AIM_TIME = 1.5  # Laser warning duration

var in_position: bool = false
var aiming_at: Player = null
var aim_timer: float = 0.0
var laser_sight: Line2D

func _ready():
	super._ready()
	
	# Laser sight visual
	laser_sight = Line2D.new()
	laser_sight.width = 2.0
	laser_sight.default_color = Color.RED
	laser_sight.visible = false
	add_child(laser_sight)

func _ai_chase_and_shoot(delta: float):
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	# Find cover position (avoid moving too much)
	if not in_position:
		var cover_pos = _find_cover_position()
		if global_position.distance_to(cover_pos) > 10:
			velocity = (cover_pos - global_position).normalized() * SNIPER_SPEED
			global_position += velocity * delta
		else:
			in_position = true
			velocity = Vector2.ZERO
	
	# Aim and shoot
	if in_position and dist < SNIPER_RANGE:
		rotation = to_player.angle()
		
		if aiming_at != target_player:
			aiming_at = target_player
			aim_timer = SNIPER_AIM_TIME
			laser_sight.visible = true
		
		# Update laser sight
		laser_sight.clear_points()
		laser_sight.add_point(Vector2.ZERO)
		laser_sight.add_point(to_player.normalized() * dist)
		
		aim_timer -= delta
		
		if aim_timer <= 0:
			wants_to_shoot.emit(to_player.normalized())
			_shoot_cooldown = 4.0  # Slow fire rate
			aiming_at = null
			laser_sight.visible = false
```

### 4. Swarm (Weak, Group Behavior)
**Role**: Overwhelm with numbers, flank  
**Behavior**: Surround target, attack from multiple angles

```gdscript
# entities/EnemySwarm.gd
extends Enemy
class_name EnemySwarm

const SWARM_SPEED = 120.0  # 1.5x normal
const SWARM_HEALTH = 50.0  # 0.33x normal
const SWARM_DAMAGE = 10.0  # 0.4x normal
const SWARM_PACK_RADIUS = 200.0

var pack_members: Array[EnemySwarm] = []
var flank_angle: float = 0.0

func _ready():
	super._ready()
	# Find pack members on spawn
	call_deferred("_find_pack")

func _find_pack():
	for entity in Replication.get_all_entities():
		if entity is EnemySwarm and entity != self:
			if global_position.distance_to(entity.global_position) < SWARM_PACK_RADIUS:
				pack_members.append(entity)

func _ai_chase_and_shoot(delta: float):
	if not target_player:
		return
	
	# Assign flank positions based on pack index
	var my_index = pack_members.find(self)
	if my_index >= 0:
		flank_angle = (my_index / float(pack_members.size())) * TAU
	
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	# Approach from flank angle
	var flank_offset = Vector2(cos(flank_angle), sin(flank_angle)) * 100
	var target_pos = target_player.global_position + flank_offset
	var to_target = target_pos - global_position
	
	velocity = to_target.normalized() * SWARM_SPEED
	global_position += velocity * delta
	rotation = to_player.angle()
	
	# Close range rapid fire
	if dist < 150 and _shoot_cooldown <= 0:
		wants_to_shoot.emit(to_player.normalized())
		_shoot_cooldown = 0.3  # Very fast
```

### 5. Healer (Support)
**Role**: Heal other enemies, buff nearby units  
**Behavior**: Stays behind frontline, heals low-HP enemies

```gdscript
# entities/EnemyHealer.gd
extends Enemy
class_name EnemyHealer

const HEALER_SPEED = 70.0
const HEALER_HEALTH = 120.0
const HEALER_HEAL_AMOUNT = 30.0
const HEALER_HEAL_COOLDOWN = 5.0
const HEALER_HEAL_RANGE = 300.0

var heal_cooldown: float = 0.0
var heal_target: Enemy = null

func _physics_process(delta: float):
	super._physics_process(delta)
	
	if not is_authority():
		return
	
	heal_cooldown -= delta
	
	if heal_cooldown <= 0:
		_try_heal()

func _try_heal():
	# Find lowest HP ally in range
	var lowest_hp = INF
	heal_target = null
	
	for entity in Replication.get_all_entities():
		if entity is Enemy and entity != self:
			var dist = global_position.distance_to(entity.global_position)
			if dist < HEALER_HEAL_RANGE:
				var hp_pct = entity.health / entity.max_health
				if hp_pct < lowest_hp and hp_pct < 0.7:  # Only heal if <70%
					lowest_hp = hp_pct
					heal_target = entity
	
	if heal_target:
		heal_target.health = min(heal_target.health + HEALER_HEAL_AMOUNT, heal_target.max_health)
		heal_cooldown = HEALER_HEAL_COOLDOWN
		
		# Visual effect
		_spawn_heal_effect(heal_target.global_position)

func _ai_chase_and_shoot(delta: float):
	# Stay behind other enemies
	var frontline_pos = _find_frontline_position()
	var to_frontline = frontline_pos - global_position
	
	if to_frontline.length() > 200:
		velocity = to_frontline.normalized() * HEALER_SPEED
	else:
		velocity = Vector2.ZERO
	
	global_position += velocity * delta
```

---

## Spawn Composition

```gdscript
# ServerMain.gd - Wave system
enum WaveType { BALANCED, RUSH, SNIPER_SUPPORT, TANK_WALL }

func _spawn_enemy_wave(wave_type: WaveType, spawn_pos: Vector2):
	match wave_type:
		WaveType.BALANCED:
			# 2 normal, 1 scout, 1 tank
			_spawn_enemy_of_type(EnemyScout, spawn_pos)
			_spawn_enemy_of_type(EnemyTank, spawn_pos + Vector2(40, 0))
			_spawn_enemy(spawn_pos + Vector2(-40, 0))
			_spawn_enemy(spawn_pos + Vector2(0, 40))
		
		WaveType.RUSH:
			# 6 swarm units
			for i in range(6):
				var offset = Vector2(i * 30, 0)
				_spawn_enemy_of_type(EnemySwarm, spawn_pos + offset)
		
		WaveType.SNIPER_SUPPORT:
			# 2 snipers + 1 healer + 2 normal
			_spawn_enemy_of_type(EnemySniper, spawn_pos)
			_spawn_enemy_of_type(EnemySniper, spawn_pos + Vector2(100, 0))
			_spawn_enemy_of_type(EnemyHealer, spawn_pos + Vector2(50, -50))
			_spawn_enemy(spawn_pos + Vector2(-50, 0))
			_spawn_enemy(spawn_pos + Vector2(-50, 50))
		
		WaveType.TANK_WALL:
			# 3 tanks + 1 healer
			_spawn_enemy_of_type(EnemyTank, spawn_pos)
			_spawn_enemy_of_type(EnemyTank, spawn_pos + Vector2(60, 0))
			_spawn_enemy_of_type(EnemyTank, spawn_pos + Vector2(-60, 0))
			_spawn_enemy_of_type(EnemyHealer, spawn_pos + Vector2(0, -80))
```

---

## Implementation Checklist

**Sprint**:
- [ ] Add stamina to Player
- [ ] Stamina bar UI
- [ ] BTN_SPRINT input mapping
- [ ] Network sync stamina state

**Enemies**:
- [ ] Scout: Kiting AI
- [ ] Tank: Charge ability + armor
- [ ] Sniper: Laser sight warning
- [ ] Swarm: Pack coordination
- [ ] Healer: Allied healing

**Balance**:
- [ ] Test sprint stamina drain
- [ ] Tune enemy health/damage
- [ ] Verify wave compositions
- [ ] Adjust spawn rates
