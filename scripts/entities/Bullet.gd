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
	# Move bullet
	global_position += velocity * delta
	
	# Decay lifetime
	lifetime -= delta
	if lifetime <= 0:
		if is_authority():
			# Server despawns
			queue_free()
		else:
			# Client despawns locally
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
