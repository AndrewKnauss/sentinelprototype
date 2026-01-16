extends RefCounted
class_name ItemRegistry

# =============================================================================
# ItemRegistry.gd - Static Item Database
# =============================================================================
# Central registry for all item definitions
# Must be initialized before any item-related code runs
# =============================================================================

static var _items: Dictionary = {}
static var _initialized: bool = false


static func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	
	# Resources (common drops from enemies/world)
	_register(ItemData.new("scrap_metal", ItemData.ItemType.RESOURCE, "Scrap Metal", 999, ItemData.Rarity.COMMON, Color(0.5, 0.5, 0.5)))
	_register(ItemData.new("electronics", ItemData.ItemType.RESOURCE, "Electronics", 999, ItemData.Rarity.UNCOMMON, Color(0.3, 0.6, 0.9)))
	_register(ItemData.new("advanced_circuits", ItemData.ItemType.RESOURCE, "Advanced Circuits", 999, ItemData.Rarity.RARE, Color(0.6, 0.3, 0.9)))
	_register(ItemData.new("ai_core", ItemData.ItemType.RESOURCE, "AI Core", 99, ItemData.Rarity.EPIC, Color(0.9, 0.5, 0.1)))
	
	# Ammo
	_register(ItemData.new("light_ammo", ItemData.ItemType.AMMO, "Light Ammo", 999, ItemData.Rarity.COMMON, Color(0.7, 0.6, 0.3)))
	_register(ItemData.new("heavy_ammo", ItemData.ItemType.AMMO, "Heavy Ammo", 999, ItemData.Rarity.UNCOMMON, Color(0.8, 0.3, 0.3)))
	_register(ItemData.new("energy_cells", ItemData.ItemType.AMMO, "Energy Cells", 999, ItemData.Rarity.RARE, Color(0.3, 0.9, 0.9)))
	
	# Consumables
	_register(ItemData.new("medkit", ItemData.ItemType.CONSUMABLE, "Medkit", 5, ItemData.Rarity.UNCOMMON, Color(0.9, 0.2, 0.2)))
	_register(ItemData.new("bandage", ItemData.ItemType.CONSUMABLE, "Bandage", 10, ItemData.Rarity.COMMON, Color(0.9, 0.9, 0.9)))
	_register(ItemData.new("stimpack", ItemData.ItemType.CONSUMABLE, "Stimpack", 3, ItemData.Rarity.RARE, Color(0.2, 0.9, 0.3)))
	
	# Buildables (for base building later)
	_register(ItemData.new("wood_wall", ItemData.ItemType.BUILDABLE, "Wood Wall", 50, ItemData.Rarity.COMMON, Color(0.6, 0.4, 0.2)))
	_register(ItemData.new("metal_wall", ItemData.ItemType.BUILDABLE, "Metal Wall", 50, ItemData.Rarity.UNCOMMON, Color(0.6, 0.6, 0.6)))
	_register(ItemData.new("door", ItemData.ItemType.BUILDABLE, "Door", 20, ItemData.Rarity.UNCOMMON, Color(0.4, 0.3, 0.2)))
	
	Log.network("ItemRegistry initialized with %d items" % _items.size())


static func _register(item: ItemData) -> void:
	_items[item.id] = item


static func get_item(item_id: String) -> ItemData:
	if not _initialized:
		initialize()
	return _items.get(item_id, null)


static func exists(item_id: String) -> bool:
	if not _initialized:
		initialize()
	return _items.has(item_id)
