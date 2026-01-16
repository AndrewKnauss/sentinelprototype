extends RefCounted
class_name PredefinedLootTables

# =============================================================================
# PredefinedLootTables.gd - Enemy Loot Table Definitions
# =============================================================================
# Static loot tables for each enemy type
# =============================================================================

static var ENEMY_NORMAL: LootTable = null
static var ENEMY_SCOUT: LootTable = null
static var ENEMY_TANK: LootTable = null
static var ENEMY_SNIPER: LootTable = null
static var ENEMY_SWARM: LootTable = null

static var _initialized: bool = false


static func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	
	# Normal enemy (balanced drops)
	ENEMY_NORMAL = LootTable.new()
	ENEMY_NORMAL.add_entry("scrap_metal", 50.0, 1, 3)      # 50% chance, 1-3
	ENEMY_NORMAL.add_entry("electronics", 30.0, 1, 2)       # 30% chance, 1-2
	ENEMY_NORMAL.add_entry("light_ammo", 25.0, 5, 15)       # 25% chance, 5-15
	ENEMY_NORMAL.add_entry("bandage", 15.0, 1, 2)           # 15% chance, 1-2
	
	# Scout (fast, low HP - less loot)
	ENEMY_SCOUT = LootTable.new()
	ENEMY_SCOUT.add_entry("scrap_metal", 40.0, 1, 2)
	ENEMY_SCOUT.add_entry("electronics", 20.0, 1, 1)
	ENEMY_SCOUT.add_entry("light_ammo", 30.0, 3, 8)
	
	# Tank (high HP - more resources)
	ENEMY_TANK = LootTable.new()
	ENEMY_TANK.add_entry("scrap_metal", 80.0, 3, 6)
	ENEMY_TANK.add_entry("electronics", 50.0, 2, 4)
	ENEMY_TANK.add_entry("advanced_circuits", 20.0, 1, 2)   # Rare drop
	ENEMY_TANK.add_entry("heavy_ammo", 40.0, 5, 12)
	ENEMY_TANK.add_entry("medkit", 15.0, 1, 1)
	
	# Sniper (precision - electronics + energy ammo)
	ENEMY_SNIPER = LootTable.new()
	ENEMY_SNIPER.add_entry("electronics", 60.0, 2, 4)
	ENEMY_SNIPER.add_entry("advanced_circuits", 30.0, 1, 2)
	ENEMY_SNIPER.add_entry("energy_cells", 40.0, 3, 8)
	ENEMY_SNIPER.add_entry("scrap_metal", 30.0, 1, 3)
	
	# Swarm (weak, fast - minimal loot)
	ENEMY_SWARM = LootTable.new()
	ENEMY_SWARM.add_entry("scrap_metal", 30.0, 1, 1)
	ENEMY_SWARM.add_entry("light_ammo", 20.0, 2, 5)
	
	Log.network("PredefinedLootTables initialized (5 enemy types)")


static func get_table_for_enemy_type(enemy_type: int) -> LootTable:
	if not _initialized:
		initialize()
	
	match enemy_type:
		0: return ENEMY_NORMAL
		1: return ENEMY_SCOUT
		2: return ENEMY_TANK
		3: return ENEMY_SNIPER
		4: return ENEMY_SWARM
		_: return ENEMY_NORMAL
