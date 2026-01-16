extends Node2D
class_name Bullet

# =============================================================================
# Bullet.gd - REFACTORED (stays as Node2D)
# =============================================================================
# Event-based projectile. Server sends spawn event, clients simulate locally.
# Uses raycasting for collision, not physics bodies.
# =============================================================================

# Networking component
var net_entity: NetworkedEntity = null
var net_id: int = 0
var authority: int = 1

# Bullet state
var velocity: Vector2 = Vector2.ZERO
var owner_id: int = 0
var damage: float = GameConstants.BULLET_DAMAGE
var lifetime: float = GameConstants.BULLET_LIFETIME

# Visuals
var _sprite: Sprite2D
static var _shared_tex: Texture2D = null


func _ready() -> void:
	# Create networking component
	net_entity = NetworkedEntity.new(self, net_id, authority, "bullet")
	
	# Create shared texture once
	if _shared_tex == null:
		var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.YELLOW)
		_shared_tex = ImageTexture.create_from_image(img)
	
	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true
	add_child(_sprite)


func _exit_tree() -> void:
	if net_entity:
		net_entity.unregister()


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


func initialize(pos: Vector2, dir: Vector2, owner: int, dmg: float = GameConstants.BULLET_DAMAGE) -> void:
	"""Initialize bullet state."""
	global_position = pos
	velocity = dir * GameConstants.BULLET_SPEED
	rotation = dir.angle()
	owner_id = owner
	damage = dmg


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
		query.collision_mask = 1  # Layer 1 = STATIC (walls)
		query.exclude = [self]
		
		var result = space.intersect_ray(query)
		if result:
			var collider = result.get("collider")
			# Check if collider has wall properties (duck typing)
			if collider and "builder_id" in collider:
				_on_hit_wall(collider)
				return true
	
	# Check player collision (circle collision)
	for entity in Replication.get_all_entities():
		if "is_local" in entity and entity.net_id != owner_id:  # Player check (has is_local property)
			if global_position.distance_to(entity.global_position) < 16:
				_on_hit_player(entity)
				return true
	
	# Check enemy collision (circle collision)
	for entity in Replication.get_all_entities():
		if "enemy_type" in entity:  # Enemy check (has enemy_type property)
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


func _on_hit_wall(wall: Node) -> void:  # Wall (weak type)
	"""Handle wall collision."""
	if Net.is_server():
		if wall.take_damage(damage):
			pass  # Wall destroyed
		Net.despawn_entity.rpc(net_id)


func _on_hit_player(player: Node) -> void:  # Player (weak type)
	"""Handle player collision."""
	if Net.is_server():
		if player.take_damage(damage):
			# Player killed - respawn
			var spawn_pos = Vector2(
				randf_range(GameConstants.SPAWN_MIN.x, GameConstants.SPAWN_MAX.x),
				randf_range(GameConstants.SPAWN_MIN.y, GameConstants.SPAWN_MAX.y)
			)
			player.respawn(spawn_pos)
		Net.despawn_entity.rpc(net_id)


func _on_hit_enemy(enemy: Node) -> void:  # Enemy (weak type)
	"""Handle enemy collision."""
	if Net.is_server():
		if enemy.take_damage(damage, owner_id):
			pass  # Enemy died
		Net.despawn_entity.rpc(net_id)
