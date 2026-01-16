extends Enemy
class_name EnemyScout

# =============================================================================
# EnemyScout.gd
# =============================================================================
# Fast, fragile enemy that maintains distance and kites players.
# Shoots while retreating when players get too close.
# =============================================================================

const SCOUT_SPEED: float = 140.0  # 1.75x base (80)
const SCOUT_HEALTH: float = 80.0  # ~0.5x base (150)
const SCOUT_DAMAGE: float = 15.0  # 0.6x base (25)
const SCOUT_RANGE: float = 500.0  # Long engage range
const SCOUT_KITE_DISTANCE: float = 300.0  # Preferred distance from target
const SCOUT_FIRE_RATE: float = 1.2  # Faster shooting


func _ready() -> void:
	_base_color = Color(1.0, 0.5, 0.0)  # Orange
	Log.entity("Scout _ready: Set _base_color to %s" % _base_color)
	super._ready()
	health = SCOUT_HEALTH
	Log.entity("Scout _ready complete: sprite.modulate = %s" % _sprite.modulate)


func _ai_chase_and_shoot(delta: float) -> void:
	"""Kiting AI - maintains distance while shooting."""
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	rotation = to_player.angle()
	
	# Kite behavior
	if dist < SCOUT_KITE_DISTANCE:
		# Too close - back away while shooting
		velocity = -to_player.normalized() * SCOUT_SPEED
	elif dist > SCOUT_RANGE:
		# Too far - approach
		velocity = to_player.normalized() * SCOUT_SPEED
	else:
		# At preferred range - strafe (perpendicular movement)
		var strafe_dir = Vector2(-to_player.y, to_player.x).normalized()
		if randf() > 0.5:
			strafe_dir = -strafe_dir
		velocity = strafe_dir * SCOUT_SPEED * 0.7
	
	# Move with collision
	move_and_slide()
	
	# Shoot frequently at long range
	if dist < SCOUT_RANGE and _shoot_cooldown <= 0:
		_shoot_cooldown = SCOUT_FIRE_RATE
		wants_to_shoot.emit(to_player.normalized())
