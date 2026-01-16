extends NetworkedEntity
class_name Enemy

# =============================================================================
# Enemy.gd
# =============================================================================
# AI-controlled enemy that moves slowly and shoots at players.
# Server-authoritative only.
# =============================================================================

signal died(enemy_id: int)
signal wants_to_shoot(direction: Vector2)

enum State { CHASE, WANDER, SEPARATE }

var health: float = GameConstants.ENEMY_MAX_HEALTH
var velocity: Vector2 = Vector2.ZERO
var target_player: Player = null

# Aggro tracking
var _damage_taken: Dictionary = {}  # player_id -> damage_dealt
var _aggro_target: Player = null
var _aggro_lock_time: float = 0.0  # Time to stick to current target

var _state: State = State.WANDER
var _state_timer: float = 0.0
var _shoot_cooldown: float = 0.0
var _wander_timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO

var _sprite: Sprite2D
var _health_bar: ColorRect
var _hurt_flash_timer: float = 0.0
var _base_color: Color = Color.DARK_RED  # Child classes can override
var _collision_body: CharacterBody2D  # For collision detection
static var _shared_tex: Texture2D = null


func _ready() -> void:
	super._ready()
	entity_type = "enemy"
	
	# Create collision body as child
	_collision_body = CharacterBody2D.new()
	_collision_body.collision_layer = 4      # Layer 3 = ENEMY (bit value 4)
	_collision_body.collision_mask = 1 | 4   # Collide with STATIC (walls) + ENEMY
	add_child(_collision_body)
	
	# Add collision shape
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 10.0  # Enemy collision radius (slightly bigger than player)
	shape.shape = circle
	_collision_body.add_child(shape)
	
	Log.entity("Enemy _ready: _base_color = %s" % _base_color)
	
	# Create shared texture once
	if _shared_tex == null:
		var img = Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)  # WHITE texture so modulation works
		_shared_tex = ImageTexture.create_from_image(img)
	
	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true
	_sprite.modulate = _base_color
	add_child(_sprite)
	
	Log.entity("Enemy _ready: sprite.modulate = %s" % _sprite.modulate)
	
	# Health bar
	_health_bar = ColorRect.new()
	_health_bar.size = Vector2(24, 3)
	_health_bar.position = Vector2(-12, -16)
	_health_bar.color = Color.RED
	add_child(_health_bar)
	
	_pick_new_wander_target()
	_state_timer = randf_range(8.0, 12.0)  # Random initial timer


func _physics_process(delta: float) -> void:
	_update_health_bar()
	
	# Hurt flash effect
	if _hurt_flash_timer > 0.0:
		_hurt_flash_timer -= delta
		var flash_intensity = _hurt_flash_timer / 0.2
		_sprite.modulate = Color.WHITE.lerp(_base_color, 1.0 - flash_intensity)
	else:
		_sprite.modulate = _base_color
	
	if not is_authority():
		return  # Only server controls AI
	
	_shoot_cooldown -= delta
	_wander_timer -= delta
	_state_timer -= delta
	_aggro_lock_time -= delta
	
	# Update target based on aggro
	target_player = _get_aggro_target()
	
	# State machine transitions
	if _state_timer <= 0:
		_transition_to_next_state()
	
	# Execute current state
	match _state:
		State.CHASE:
			if target_player:
				_ai_chase_and_shoot(delta)
			else:
				_state = State.WANDER
				_state_timer = randf_range(5.0, 8.0)
		State.WANDER:
			_ai_wander(delta)
		State.SEPARATE:
			_ai_separate(delta)


func _transition_to_next_state() -> void:
	"""Transition between states based on situation."""
	# Check if too close to other enemies
	if _is_crowded():
		_state = State.SEPARATE
		_state_timer = randf_range(3.0, 5.0)
		return
	
	# Otherwise alternate between chase and wander
	if target_player and _state != State.CHASE:
		_state = State.CHASE
		_state_timer = randf_range(8.0, 12.0)
	else:
		_state = State.WANDER
		_state_timer = randf_range(5.0, 8.0)
		_pick_new_wander_target()


func _is_crowded() -> bool:
	"""Check if too many enemies are nearby."""
	var nearby_count = 0
	for entity in Replication.get_all_entities():
		if entity is Enemy and entity != self:
			var dist = global_position.distance_to(entity.global_position)
			if dist < 60:  # Too close threshold
				nearby_count += 1
				if nearby_count >= 2:
					return true
	return false


func _ai_chase_and_shoot(delta: float) -> void:
	"""Chase player and shoot if in range."""
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	# Aim at player
	rotation = to_player.angle()
	
	# Move toward player (with some spacing)
	if dist > 200:
		velocity = to_player.normalized() * GameConstants.ENEMY_MOVE_SPEED
		
		# Calculate motion
		var motion = velocity * delta
		
		# Test collision
		_collision_body.velocity = velocity
		var collision = _collision_body.move_and_collide(motion)
		
		if collision:
			# Slide along walls
			var slide_velocity = velocity.slide(collision.get_normal())
			var slide_motion = slide_velocity * delta
			_collision_body.move_and_collide(slide_motion)
			
			# Apply child's movement to parent
			global_position += _collision_body.position
			_collision_body.position = Vector2.ZERO
		else:
			# No collision - apply full movement to parent
			global_position += motion
			_collision_body.position = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	
	# Shoot if in range and cooldown ready
	if dist < GameConstants.ENEMY_SHOOT_RANGE and _shoot_cooldown <= 0:
		_shoot_cooldown = GameConstants.ENEMY_SHOOT_COOLDOWN
		wants_to_shoot.emit(to_player.normalized())


func _ai_wander(delta: float) -> void:
	"""Random wandering when no players nearby."""
	if _wander_timer <= 0:
		_pick_new_wander_target()
	
	var to_target = _wander_target - global_position
	if to_target.length() > 10:
		velocity = to_target.normalized() * (GameConstants.ENEMY_MOVE_SPEED * 0.5)
		
		# Calculate motion
		var motion = velocity * delta
		
		# Test collision
		_collision_body.velocity = velocity
		var collision = _collision_body.move_and_collide(motion)
		
		if collision:
			# Slide along walls
			var slide_velocity = velocity.slide(collision.get_normal())
			var slide_motion = slide_velocity * delta
			_collision_body.move_and_collide(slide_motion)
			
			# Apply child's movement to parent
			global_position += _collision_body.position
			_collision_body.position = Vector2.ZERO
		else:
			# No collision - apply full movement to parent
			global_position += motion
			_collision_body.position = Vector2.ZERO
		
		rotation = to_target.angle()
	else:
		velocity = Vector2.ZERO


func _ai_separate(delta: float) -> void:
	"""Move away from other enemies to avoid clustering."""
	var separation = Vector2.ZERO
	var count = 0
	
	for entity in Replication.get_all_entities():
		if entity is Enemy and entity != self:
			var to_other = global_position - entity.global_position
			var dist = to_other.length()
			if dist < 100:  # Separation radius
				separation += to_other.normalized() / max(dist, 0.1)
				count += 1
	
	if count > 0:
		separation = separation.normalized()
		velocity = separation * GameConstants.ENEMY_MOVE_SPEED
		
		# Calculate motion
		var motion = velocity * delta
		
		# Test collision
		_collision_body.velocity = velocity
		var collision = _collision_body.move_and_collide(motion)
		
		if collision:
			# Slide along walls
			var slide_velocity = velocity.slide(collision.get_normal())
			var slide_motion = slide_velocity * delta
			_collision_body.move_and_collide(slide_motion)
			
			# Apply child's movement to parent
			global_position += _collision_body.position
			_collision_body.position = Vector2.ZERO
		else:
			# No collision - apply full movement to parent
			global_position += motion
			_collision_body.position = Vector2.ZERO
		
		rotation = separation.angle()
	else:
		# No enemies nearby, go back to wandering
		_state = State.WANDER
		_state_timer = randf_range(5.0, 8.0)


func _pick_new_wander_target() -> void:
	_wander_timer = randf_range(2.0, 5.0)
	_wander_target = Vector2(
		randf_range(100, 900),
		randf_range(100, 500)
	)


func _find_nearest_player() -> Player:
	var nearest: Player = null
	var nearest_dist = INF
	
	for entity in Replication.get_all_entities():
		if entity is Player:
			var dist = global_position.distance_to(entity.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = entity
	
	return nearest


func _get_aggro_target() -> Player:
	"""Get target based on aggro system with sticky targeting."""
	
	# If we have a locked aggro target and they're still valid
	if _aggro_lock_time > 0.0 and _aggro_target and is_instance_valid(_aggro_target):
		# Keep locked unless they're too far away
		var dist = global_position.distance_to(_aggro_target.global_position)
		if dist < GameConstants.ENEMY_AGGRO_RANGE:
			return _aggro_target
	
	# Lock expired or target invalid - recalculate
	_aggro_target = null
	_aggro_lock_time = 0.0
	
	# Find player who has dealt most damage
	var top_damage = 0.0
	var top_attacker: Player = null
	
	for player_id in _damage_taken:
		var damage = _damage_taken[player_id]
		if damage > top_damage:
			# Find the player entity
			for entity in Replication.get_all_entities():
				if entity is Player and entity.net_id == player_id:
					top_damage = damage
					top_attacker = entity
					break
	
	# If someone has damaged us, target them
	if top_attacker:
		return top_attacker
	
	# Otherwise, find nearest player
	return _find_nearest_player()


func take_damage(amount: float, attacker_id: int = 0) -> bool:
	"""Apply damage. Returns true if killed."""
	health -= amount
	_hurt_flash_timer = 0.2  # Flash white for 0.2 seconds
	
	# Track damage for aggro
	if attacker_id > 0:
		if not _damage_taken.has(attacker_id):
			_damage_taken[attacker_id] = 0.0
		_damage_taken[attacker_id] += amount
		
		# Lock aggro to this attacker
		for entity in Replication.get_all_entities():
			if entity is Player and entity.net_id == attacker_id:
				_aggro_target = entity
				_aggro_lock_time = GameConstants.ENEMY_AGGRO_LOCK_TIME
				
				# IMMEDIATELY switch to chase state when taking damage
				if _state != State.CHASE:
					_state = State.CHASE
					_state_timer = randf_range(8.0, 12.0)
				
				break
	
	if health <= 0:
		health = 0
		died.emit(net_id)
		return true
	return false


func get_replicated_state() -> Dictionary:
	return {
		"p": global_position,
		"r": rotation,
		"h": health,
		"v": velocity
	}


func apply_replicated_state(state: Dictionary) -> void:
	global_position = state.get("p", global_position)
	rotation = state.get("r", rotation)
	
	# Check if health decreased (took damage)
	var new_health = state.get("h", health)
	if new_health < health:
		_hurt_flash_timer = 0.2  # Trigger flash on damage
	health = new_health
	
	velocity = state.get("v", velocity)


func _update_health_bar() -> void:
	var pct = health / GameConstants.ENEMY_MAX_HEALTH
	_health_bar.size.x = 24 * pct
	if pct > 0.6:
		_health_bar.color = Color.RED
	elif pct > 0.3:
		_health_bar.color = Color.ORANGE
	else:
		_health_bar.color = Color.DARK_RED
