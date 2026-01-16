extends Node2D
class_name ItemDrop

# =============================================================================
# ItemDrop.gd - Physical Loot Entity
# =============================================================================
# Represents an item that can be picked up from the ground
# Server-authoritative, clients interpolate
# =============================================================================

# Networking component
var net_entity: NetworkedEntity = null
var net_id: int = 0
var authority: int = 1

# Item data
var item_id: String = ""
var quantity: int = 1

# Lifetime (server only)
var _lifetime: float = 0.0
const MAX_LIFETIME: float = 300.0  # 5 minutes before despawn

# Visuals
var _sprite: Sprite2D
var _label: Label

static var _shared_tex: Texture2D = null


func _ready() -> void:
	# Create networking component
	net_entity = NetworkedEntity.new(self, net_id, authority, "item_drop")
	
	# Create shared texture (simple square)
	if _shared_tex == null:
		var img = Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_shared_tex = ImageTexture.create_from_image(img)
	
	# Visual setup
	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true
	add_child(_sprite)
	
	# Set color based on rarity
	_update_visuals()
	
	# Label showing quantity
	_label = Label.new()
	_label.position = Vector2(-8, 8)
	_label.scale = Vector2(0.6, 0.6)
	add_child(_label)
	_update_label()


func _update_visuals():
	if not _sprite:
		return
	
	var item_def = ItemRegistry.get_item(item_id)
	if item_def:
		_sprite.modulate = item_def.icon_color
	else:
		_sprite.modulate = Color.WHITE


func _update_label():
	if not _label:
		return
	
	if quantity > 1:
		_label.text = "x%d" % quantity
		_label.visible = true
	else:
		_label.visible = false


# Server-only: tick lifetime
func tick_lifetime(delta: float) -> bool:
	if authority != 1:
		return false
	
	_lifetime += delta
	return _lifetime >= MAX_LIFETIME


# Get replicated state (for snapshots)
func get_replicated_state() -> Dictionary:
	return {
		"p": global_position,
		"r": rotation,
		"item_id": item_id,
		"qty": quantity
	}


# Apply replicated state (from server snapshot)
func apply_replicated_state(state: Dictionary):
	if state.has("p"):
		global_position = state.p
	if state.has("r"):
		rotation = state.r
	if state.has("item_id") and state.item_id != item_id:
		item_id = state.item_id
		_update_visuals()
	if state.has("qty") and state.qty != quantity:
		quantity = state.qty
		_update_label()


# Cleanup
func _exit_tree():
	if net_entity:
		net_entity.unregister()
