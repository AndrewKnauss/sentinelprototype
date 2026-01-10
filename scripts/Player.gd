extends Node2D
class_name Player

var net_id: int = 0
var is_local: bool = false

var velocity: Vector2 = Vector2.ZERO
var rotation_rad: float = 0.0

# Tweakable constants
const MOVE_SPEED := 220.0

# Visuals created at runtime, so you don't need any scenes/assets.
var _sprite: Sprite2D
var _label: Label

static var _shared_tex: Texture2D

func _ready() -> void:
	# Make a tiny 16x16 white texture once, reuse for all sprites.
	if _shared_tex == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_shared_tex = ImageTexture.create_from_image(img)

	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true
	_sprite.scale = Vector2(1.0, 1.0)

	# Color based on net_id; local is brighter.
	var c := _color_from_id(net_id)
	if is_local:
		c = c.lerp(Color(1, 1, 1, 1), 0.35)
	_sprite.modulate = c
	add_child(_sprite)

	_label = Label.new()
	_label.text = str(net_id)
	_label.position = Vector2(-10, -26)
	_label.scale = Vector2(0.8, 0.8)
	add_child(_label)

func apply_input(mv: Vector2, aim: Vector2, _buttons: int, dt: float) -> void:
	if mv.length() > 1.0:
		mv = mv.normalized()

	velocity = mv * MOVE_SPEED
	global_position += velocity * dt

	if aim.length() > 0.001:
		rotation_rad = aim.angle()
	rotation = rotation_rad

func get_state() -> Dictionary:
	return {
		"p": global_position,
		"v": velocity,
		"r": rotation_rad
	}

func set_state(s: Dictionary) -> void:
	global_position = s.get("p", global_position)
	velocity = s.get("v", velocity)
	rotation_rad = float(s.get("r", rotation_rad))
	rotation = rotation_rad

func _color_from_id(id: int) -> Color:
	# Deterministic pseudo-random color from id.
	var x := int(id) * 1103515245 + 12345
	var r := float((x >> 16) & 255) / 255.0
	x = x * 1103515245 + 12345
	var g := float((x >> 16) & 255) / 255.0
	x = x * 1103515245 + 12345
	var b := float((x >> 16) & 255) / 255.0
	# Keep them not-too-dark
	return Color(0.25 + 0.75 * r, 0.25 + 0.75 * g, 0.25 + 0.75 * b, 1.0)
