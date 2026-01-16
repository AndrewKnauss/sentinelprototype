extends Enemy
class_name EnemySniper

# =============================================================================
# EnemySniper.gd
# =============================================================================
# Long-range enemy with laser sight warning before high-damage shots.
# Prefers stationary positioning. Laser is client-side visual only.
# =============================================================================

const SNIPER_SPEED: float = 60.0  # Slow repositioning
const SNIPER_HEALTH: float = 100.0  # Fragile
const SNIPER_DAMAGE: float = 60.0  # 2.4x base - high burst
const SNIPER_RANGE: float = 700.0  # Very long
const SNIPER_AIM_TIME: float = 1.5  # Laser warning duration
const SNIPER_FIRE_RATE: float = 4.0  # Slow between shots

var _in_position: bool = false
var _is_aiming: bool = false
var _aim_timer: float = 0.0
var _laser_line: Line2D


func _ready() -> void:
	enemy_type = 3  # Sniper
	_base_color = Color(0.8, 0.0, 0.8)  # Magenta
	super._ready()
	health = SNIPER_HEALTH
	
	# Laser sight visual
	_laser_line = Line2D.new()
	_laser_line.width = 2.0
	_laser_line.default_color = Color(1.0, 0.0, 0.0, 0.5)  # Semi-transparent red
	_laser_line.visible = false
	add_child(_laser_line)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if not net_entity.is_authority():
		# Client needs to check aiming timer
		if _is_aiming:
			_aim_timer -= delta
	
	# Update laser visual (both server and client)
	if _is_aiming:
		# On clients, target_player might not be set, so find nearest player
		var aim_target = target_player
		if not aim_target or not is_instance_valid(aim_target):
			aim_target = _find_nearest_player()
		
		if aim_target and is_instance_valid(aim_target):
			var to_target = aim_target.global_position - global_position
			var dist = min(to_target.length(), SNIPER_RANGE)
			# Line2D is rotated with parent, so use local direction
			_laser_line.clear_points()
			_laser_line.add_point(Vector2.ZERO)
			_laser_line.add_point(Vector2.RIGHT * dist)  # Local space
			_laser_line.visible = true
		else:
			_laser_line.visible = false
	else:
		_laser_line.visible = false
	
	if net_entity.is_authority() and _is_aiming:
		_aim_timer -= delta


func _ai_chase_and_shoot(delta: float) -> void:
	"""Stationary sniping with aim delay."""
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	rotation = to_player.angle()
	
	# Position logic - try to stay still once in range
	if dist > SNIPER_RANGE:
		# Too far - approach slowly
		_in_position = false
		velocity = to_player.normalized() * SNIPER_SPEED
		move_and_slide()
	elif dist < 300:
		# Too close - back away
		_in_position = false
		velocity = -to_player.normalized() * SNIPER_SPEED
		move_and_slide()
	else:
		# Good range - stay still
		_in_position = true
		velocity = Vector2.ZERO
	
	# Aiming and shooting
	if _in_position and dist <= SNIPER_RANGE:
		if not _is_aiming and _shoot_cooldown <= 0:
			# Start aiming
			_is_aiming = true
			_aim_timer = SNIPER_AIM_TIME
		
		if _is_aiming:
			if _aim_timer <= 0:
				# Fire!
				wants_to_shoot.emit(to_player.normalized())
				_shoot_cooldown = SNIPER_FIRE_RATE
				_is_aiming = false


func get_replicated_state() -> Dictionary:
	var state = super.get_replicated_state()
	state["aiming"] = _is_aiming
	state["aim_t"] = _aim_timer
	return state


func apply_replicated_state(state: Dictionary) -> void:
	super.apply_replicated_state(state)
	var was_aiming = _is_aiming
	_is_aiming = state.get("aiming", false)
	_aim_timer = state.get("aim_t", 0.0)
	
	if _is_aiming != was_aiming:
		Log.entity("Sniper %d aiming changed: %s -> %s" % [net_id, was_aiming, _is_aiming])
