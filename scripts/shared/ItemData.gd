extends RefCounted
class_name ItemData

# =============================================================================
# ItemData.gd - Item Definition System
# =============================================================================
# Defines all item types, properties, and provides registry for lookup
# =============================================================================

# Item types
enum ItemType {
	WEAPON,
	AMMO,
	RESOURCE,
	CONSUMABLE,
	BUILDABLE
}

# Rarity levels
enum Rarity {
	COMMON,      # Gray
	UNCOMMON,    # Green
	RARE,        # Blue
	EPIC,        # Purple
	LEGENDARY    # Orange
}

# Item properties
var id: String = ""
var type: ItemType = ItemType.RESOURCE
var name: String = ""
var stack_size: int = 1
var rarity: Rarity = Rarity.COMMON
var icon_color: Color = Color.GRAY  # Temporary until we have real icons

func _init(p_id: String, p_type: ItemType, p_name: String, p_stack: int, p_rarity: Rarity, p_color: Color = Color.GRAY):
	id = p_id
	type = p_type
	name = p_name
	stack_size = p_stack
	rarity = p_rarity
	icon_color = p_color
