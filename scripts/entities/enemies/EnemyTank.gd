extends Enemy
class_name EnemyTank

# =============================================================================
# EnemyTank.gd
# =============================================================================
# Slow, high HP enemy with armor and charge ability.
# Absorbs damage and bodyblocks for other enemies.
# =============================================================================

const TANK_SPEED: float = 50.0  # 0.625x base
const TANK_HEALTH: float = 400.0  # 2.67x base
const TANK_DAMAGE: float = 35.0  # 1.4x base
const TANK_ARMOR: float = 0.6  # Takes 60% damage
const TANK_CHARGE_SPEED: float = 200.0  # 2.5x base during charge
const TANK_CHARGE_DURATION: float = 2.0
const TANK_CHARGE_COOLDOWN: float = 8.0
const TANK_CHARGE_MIN_DIST: float = 100.0
const TANK_CHARGE_MAX_DIST: float = 400.0

var _is_charging: bool = false
var _charge_timer: float = 0.0
var _charge_cooldown: float = 0.0


func _ready() -> void:
	_base_color = Color(0.5, 0.5, 0.5)  # Gray
	super._ready()
	health = TANK_HEALTH
	_sprite.scale = Vector2(1.5, 1.5)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if not net_entity.is_authority():
		return
	
	_charge_cooldown -= delta
	
	if _is_charging:
		_charge_timer -= delta
		if _charge_timer <= 0:
			_is_charging = false


func take_damage(amount: float, attacker_id: int = 0) -> bool:
	# Apply armor reduction
	amount *= TANK_ARMOR
	return super.take_damage(amount, attacker_id)


func _ai_chase_and_shoot(delta: float) -> void:
	"""Aggressive charge towards target."""
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	rotation = to_player.angle()
	
	# Try to initiate charge
	if not _is_charging and _charge_cooldown <= 0:
		if dist >= TANK_CHARGE_MIN_DIST and dist <= TANK_CHARGE_MAX_DIST:
			_is_charging = true
			_charge_timer = TANK_CHARGE_DURATION
			_charge_cooldown = TANK_CHARGE_COOLDOWN
	
	# Apply movement
	if _is_charging:
		velocity = to_player.normalized() * TANK_CHARGE_SPEED
	else:
		velocity = to_player.normalized() * TANK_SPEED
	
	# Move with collision
	move_and_slide()
	
	# Melee-focused attacks
	if dist < 80 and _shoot_cooldown <= 0:
		_shoot_cooldown = 0.5  # Fast melee swings
		wants_to_shoot.emit(to_player.normalized())
