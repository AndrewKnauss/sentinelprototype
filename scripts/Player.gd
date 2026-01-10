extends Node2D
class_name Player

# =============================================================================
# Player.gd
# =============================================================================
# LONG DESCRIPTION:
# This is a deliberately "dumb" entity:
# - It stores its own minimal state (position/velocity/rotation).
# - It can apply movement input (mv + aim) for both server sim and client prediction.
# - It can produce a compact serializable "state dictionary" for replication snapshots.
#
# IMPORTANT:
# Right now, Player is both "model" and "view" because it draws a square + label.
# Later, when you modularize business logic, a good next step is splitting into:
#   - PlayerModel (pure data / pure simulation)
#   - PlayerView  (sprite/label/animation)
# For prototyping, keeping it in one script is fine.
# =============================================================================

# The network ID this entity represents (peer_id).
var net_id: int = 0

# True only on the local client for the local player.
# This is used only for visuals (color/brightness).
var is_local: bool = false

# Current velocity used by simple kinematic motion.
var velocity: Vector2 = Vector2.ZERO

# We keep rotation in radians explicitly for clarity.
var rotation_rad: float = 0.0

# Movement tuning.
const MOVE_SPEED: float = 220.0

# Visual components created in code so you don't need separate scenes/assets.
var _sprite: Sprite2D
var _label: Label

# A shared texture for all players to avoid allocating per player.
static var _shared_tex: Texture2D = null


# -----------------------------------------------------------------------------
# _ready()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Initialize visuals (sprite + id label).
# - Generate a shared white texture once.
# - Set a deterministic color based on net_id so each player is distinguishable.
#
# WHERE CALLED:
# - Godot calls _ready() when the node enters the scene tree.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _ready() -> void:
	# Make a tiny 16x16 white texture once, reuse for all sprites.
	if _shared_tex == null:
		var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_shared_tex = ImageTexture.create_from_image(img)

	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true

	# Color based on net_id; local is slightly brighter for easier identification.
	var c: Color = _color_from_id(net_id)
	if is_local:
		c = c.lerp(Color(1, 1, 1, 1), 0.35)
	_sprite.modulate = c
	add_child(_sprite)

	_label = Label.new()
	_label.text = str(net_id)
	_label.position = Vector2(-10, -26)
	_label.scale = Vector2(0.8, 0.8)
	add_child(_label)


# -----------------------------------------------------------------------------
# apply_input(mv, aim, buttons, dt)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Apply a single "input command" to advance this player by dt seconds.
# - This same function is used in THREE places:
#   (1) On the server: authoritative simulation (truth)
#   (2) On the local client: prediction (instant feel)
#   (3) On the client during reconciliation: replaying stored inputs
#
# PARAMETERS:
# - mv: Vector2 movement intent (typically from WASD/arrow keys), usually normalized.
# - aim: Vector2 direction intent (mouse aim direction), normalized if non-zero.
# - buttons: bitmask of actions (shoot/interact/etc.) - unused for now.
# - dt: timestep in seconds (usually 1 / physics_ticks_per_second).
#
# RETURNS:
# - Nothing. It mutates this node's position/rotation/velocity.
#
# WHY:
# - Keeping this deterministic and identical across server and client is what makes
#   prediction + reconciliation work.
# -----------------------------------------------------------------------------
func apply_input(mv: Vector2, aim: Vector2, _buttons: int, dt: float) -> void:
	# Safety clamp: never allow > 1 magnitude (prevents "speed hacks" if server uses it too).
	if mv.length() > 1.0:
		mv = mv.normalized()

	# Very simple kinematic movement (no collisions).
	velocity = mv * MOVE_SPEED
	global_position += velocity * dt

	# Rotate to aim direction if provided
	if aim.length() > 0.001:
		rotation_rad = aim.angle()
	rotation = rotation_rad


# -----------------------------------------------------------------------------
# get_state()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Produce a compact dictionary representing this entity’s replicated state.
# - This is what gets inserted into server snapshots and sent to clients.
#
# WHERE CALLED:
# - ServerMain builds snapshots: states[peer_id] = player.get_state()
# - ClientMain stores/sets state for spawns and snapshots
#
# RETURNS:
# - Dictionary with keys:
#     "p": position (Vector2)
#     "v": velocity (Vector2)
#     "r": rotation radians (float)
#
# WHY:
# - A small stable state format keeps networking simple and efficient.
# -----------------------------------------------------------------------------
func get_state() -> Dictionary:
	return {
		"p": global_position,
		"v": velocity,
		"r": rotation_rad
	}


# -----------------------------------------------------------------------------
# set_state(s)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Apply a replicated state dictionary to this entity.
# - Used by clients when:
#   - receiving a spawn message
#   - receiving snapshots (for remote players)
#   - rewinding to server truth during reconciliation (local player)
#
# PARAMETERS:
# - s: Dictionary (must match get_state() format)
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func set_state(s: Dictionary) -> void:
	global_position = s.get("p", global_position)
	velocity = s.get("v", velocity)
	rotation_rad = float(s.get("r", rotation_rad))
	rotation = rotation_rad


# -----------------------------------------------------------------------------
# _color_from_id(id)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Deterministically generate a visible color from an integer ID.
# - This is purely cosmetic.
#
# WHERE CALLED:
# - _ready()
#
# RETURNS:
# - Color: a bright-ish color so squares are distinguishable.
# -----------------------------------------------------------------------------
func _color_from_id(id: int) -> Color:
	var x: int = id * 1103515245 + 12345

	var r: float = float((x >> 16) & 255) / 255.0
	x = x * 1103515245 + 12345
	var g: float = float((x >> 16) & 255) / 255.0
	x = x * 1103515245 + 12345
	var b: float = float((x >> 16) & 255) / 255.0

	# Keep them not-too-dark.
	return Color(0.25 + 0.75 * r, 0.25 + 0.75 * g, 0.25 + 0.75 * b, 1.0)
