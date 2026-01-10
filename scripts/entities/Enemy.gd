extends NetworkedEntity
class_name Enemy

# =============================================================================
# Enemy.gd
# =============================================================================
# AI-controlled enemy that moves slowly and shoots at players.
# Server-authoritative only.
# =============================================================================

signal died(enemy_id: int)

var health: float = GameConstants.ENEMY_MAX_HEALTH
var velocity: Vector2 = Vector2.ZERO
var target_player: Player = null

var _shoot_cooldown: float = 0.0
var _wander_timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO

var _sprite: Sprite2D
var _health_bar: ColorRect
static var _shared_tex: Texture2D = null


func _ready() -> void:
	super._ready()
	entity_type = "enemy"
	
	# Create shared texture once
	if _shared_tex == null:
		var img = Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(Color.RED)
		_shared_tex = ImageTexture.create_from_image(img)
	
	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true
	_sprite.modulate = Color.DARK_RED
	add_child(_sprite)
	
	# Health bar
	_health_bar = ColorRect.new()
	_health_bar.size = Vector2(24, 3)
	_health_bar.position = Vector2(-12, -16)
	_health_bar.color = Color.RED
	add_child(_health_bar)
	
	_pick_new_wander_target()


func _physics_process(delta: float) -> void:
	if not is_authority():
		_update_health_bar()
		return  # Only server controls AI
	
	_shoot_cooldown -= delta
	_wander_timer -= delta
	
	# Find nearest player
	target_player = _find_nearest_player()
	
	if target_player:
		_ai_chase_and_shoot(delta)
	else:
		_ai_wander(delta)
	
	_update_health_bar()


func _ai_chase_and_shoot(delta: float) -> void:
	"""Chase player and shoot if in range."""
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	# Aim at player
	rotation = to_player.angle()
	
	# Move toward player
	if dist > 200:
		velocity = to_player.normalized() * GameConstants.ENEMY_MOVE_SPEED
		global_position += velocity * delta
	else:
		velocity = Vector2.ZERO
	
	# Shoot if in range
	if dist < GameConstants.ENEMY_SHOOT_RANGE and _shoot_cooldown <= 0:
		shoot()


func _ai_wander(delta: float) -> void:
	"""Random wandering when no players nearby."""
	if _wander_timer <= 0:
		_pick_new_wander_target()
	
	var to_target = _wander_target - global_position
	if to_target.length() > 10:
		velocity = to_target.normalized() * (GameConstants.ENEMY_MOVE_SPEED * 0.5)
		global_position += velocity * delta
		rotation = to_target.angle()
	else:
		velocity = Vector2.ZERO


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


func shoot() -> bool:
	"""Attempt to shoot. Returns true if shot fired."""
	if _shoot_cooldown > 0:
		return false
	
	_shoot_cooldown = GameConstants.ENEMY_SHOOT_COOLDOWN
	return true


func take_damage(amount: float) -> bool:
	"""Apply damage. Returns true if killed."""
	health -= amount
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
	health = state.get("h", health)
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
