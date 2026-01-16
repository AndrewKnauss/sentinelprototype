extends NetworkedEntity
class_name Wall

# =============================================================================
# Wall.gd
# =============================================================================
# Buildable wall structure that blocks bullets.
# Uses StaticBody2D for collision detection.
# =============================================================================

signal destroyed(wall_id: int)

var health: float = GameConstants.WALL_MAX_HEALTH
var builder_id: int = 0  # Who built this wall (runtime peer_id)
var builder_username: String = ""  # Builder's username (for persistence)

var _sprite: ColorRect
var _health_bar: ColorRect
var _collision: StaticBody2D
var _shape: CollisionShape2D


func _ready() -> void:
	super._ready()
	entity_type = "wall"
	
	# Visual
	_sprite = ColorRect.new()
	_sprite.size = GameConstants.WALL_SIZE
	_sprite.position = -GameConstants.WALL_SIZE / 2  # Center it
	_sprite.color = Color(0.5, 0.5, 0.5, 0.8)
	add_child(_sprite)
	
	# Health bar
	_health_bar = ColorRect.new()
	_health_bar.size = Vector2(GameConstants.WALL_SIZE.x, 4)
	_health_bar.position = Vector2(-GameConstants.WALL_SIZE.x / 2, -GameConstants.WALL_SIZE.y / 2 - 8)
	_health_bar.color = Color.CYAN
	add_child(_health_bar)
	
	# Collision (blocks bullets)
	_collision = StaticBody2D.new()
	_collision.collision_layer = 2  # Walls on layer 2
	_collision.collision_mask = 0
	add_child(_collision)
	
	_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = GameConstants.WALL_SIZE
	_shape.shape = rect
	_collision.add_child(_shape)


func _process(_delta: float) -> void:
	_update_health_bar()


func take_damage(amount: float) -> bool:
	"""Apply damage. Returns true if destroyed."""
	health -= amount
	if health <= 0:
		health = 0
		destroyed.emit(net_id)
		return true
	return false


func get_replicated_state() -> Dictionary:
	return {
		"p": global_position,
		"h": health,
		"b": builder_id
	}


func apply_replicated_state(state: Dictionary) -> void:
	global_position = state.get("p", global_position)
	health = state.get("h", health)
	builder_id = state.get("b", builder_id)


func _update_health_bar() -> void:
	var pct = health / GameConstants.WALL_MAX_HEALTH
	_health_bar.size.x = GameConstants.WALL_SIZE.x * pct
	if pct > 0.6:
		_health_bar.color = Color.CYAN
	elif pct > 0.3:
		_health_bar.color = Color.YELLOW
	else:
		_health_bar.color = Color.RED
