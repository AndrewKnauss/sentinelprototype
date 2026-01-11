extends NetworkedEntity
class_name Bullet

# =============================================================================
# Bullet.gd
# =============================================================================
# Event-based projectile. Server sends spawn event, clients simulate locally.
# =============================================================================

var velocity: Vector2 = Vector2.ZERO
var owner_id: int = 0  # Who fired this bullet
var lifetime: float = GameConstants.BULLET_LIFETIME

var _sprite: Sprite2D
static var _shared_tex: Texture2D = null


func _ready() -> void:
	super._ready()
	entity_type = "bullet"
	
	# Create shared texture once
	if _shared_tex == null:
		var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.YELLOW)
		_shared_tex = ImageTexture.create_from_image(img)
	
	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	# Check collisions BEFORE moving
	if _check_collision():
		queue_free()
		return
	
	# Move bullet
	global_position += velocity * delta
	
	# Decay lifetime
	lifetime -= delta
	if lifetime <= 0:
		queue_free()


func initialize(pos: Vector2, dir: Vector2, owner: int) -> void:
	"""Initialize bullet state."""
	global_position = pos
	velocity = dir * GameConstants.BULLET_SPEED
	rotation = dir.angle()
	owner_id = owner


func get_replicated_state() -> Dictionary:
	return {
		"p": global_position,
		"r": rotation,
		"v": velocity,
		"o": owner_id,
		"l": lifetime
	}


func apply_replicated_state(state: Dictionary) -> void:
	global_position = state.get("p", global_position)
	rotation = state.get("r", rotation)
	velocity = state.get("v", velocity)
	owner_id = state.get("o", owner_id)
	lifetime = state.get("l", lifetime)


func _check_collision() -> bool:
	"""Check for bullet collisions. Returns true if hit something."""
	# Use raycast for wall collision
	var space = get_world_2d().direct_space_state
	if space:
		var query = PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + velocity.normalized() * 10
		)
		query.collision_mask = 2  # Layer 2 = walls
		query.exclude = [self]
		
		var result = space.intersect_ray(query)
		if result:
			var collider = result.get("collider")
			if collider and collider.get_parent() is Wall:
				var wall = collider.get_parent() as Wall
				_on_hit_wall(wall)
				return true
	
	# Check player collision (circle collision)
	for entity in Replication.get_all_entities():
		if entity is Player and entity.net_id != owner_id:
			if global_position.distance_to(entity.global_position) < 16:
				_on_hit_player(entity)
				return true
	
	# Check enemy collision (circle collision)
	for entity in Replication.get_all_entities():
		if entity is Enemy:
			# Check friendly fire rules
			var can_damage = false
			if owner_id != 0:  # Player bullet
				can_damage = true
			elif GameConstants.ENEMY_FRIENDLY_FIRE:  # Enemy bullet with FF enabled
				can_damage = true
			
			if can_damage and global_position.distance_to(entity.global_position) < 20:
				_on_hit_enemy(entity)
				return true
	
	return false


func _on_hit_wall(wall: Wall) -> void:
	"""Handle wall collision."""
	if Net.is_server():
		# Server: Apply damage
		if wall.take_damage(GameConstants.BULLET_DAMAGE):
			# Wall destroyed - it will emit destroyed signal
			pass
		# Tell clients to despawn this bullet
		Net.despawn_entity.rpc(net_id)
	else:
		# Client: Just despawn visually (server is authoritative)
		pass


func _on_hit_player(player: Player) -> void:
	"""Handle player collision."""
	if Net.is_server():
		# Server: Apply damage
		if player.take_damage(GameConstants.BULLET_DAMAGE):
			# Player killed - need to respawn
			var spawn_pos = Vector2(
				randf_range(GameConstants.SPAWN_MIN.x, GameConstants.SPAWN_MAX.x),
				randf_range(GameConstants.SPAWN_MIN.y, GameConstants.SPAWN_MAX.y)
			)
			player.respawn(spawn_pos)
		# Tell clients to despawn this bullet
		Net.despawn_entity.rpc(net_id)
	else:
		# Client: Just despawn visually (server is authoritative for damage)
		pass


func _on_hit_enemy(enemy: Enemy) -> void:
	"""Handle enemy collision."""
	if Net.is_server():
		# Server: Apply damage
		if enemy.take_damage(GameConstants.BULLET_DAMAGE):
			# Enemy killed - it will emit died signal which ServerMain handles
			pass
		# Tell clients to despawn this bullet
		Net.despawn_entity.rpc(net_id)
	else:
		# Client: Just despawn visually (server is authoritative for damage)
		pass
