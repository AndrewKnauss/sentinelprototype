# Player Progression & Skills

## Skill Tree

```gdscript
# shared/SkillData.gd
enum SkillType { COMBAT, BUILDER, SCAVENGER }

const SKILLS = {
	# Combat tree
	"max_health": {"type": COMBAT, "max_level": 5, "bonus_per_level": 20.0, "cost": [10, 20, 40, 80, 160]},
	"damage_boost": {"type": COMBAT, "max_level": 5, "bonus_per_level": 0.1, "cost": [15, 30, 60, 120, 240]},
	"sprint_efficiency": {"type": COMBAT, "max_level": 3, "bonus_per_level": 0.2, "cost": [20, 40, 80]},
	
	# Builder tree
	"structure_health": {"type": BUILDER, "max_level": 5, "bonus_per_level": 0.2, "cost": [10, 20, 40, 80, 160]},
	"build_cost_reduction": {"type": BUILDER, "max_level": 4, "bonus_per_level": 0.1, "cost": [15, 30, 60, 120]},
	"repair_speed": {"type": BUILDER, "max_level": 3, "bonus_per_level": 0.3, "cost": [20, 40, 80]},
	
	# Scavenger tree
	"loot_radius": {"type": SCAVENGER, "max_level": 3, "bonus_per_level": 20.0, "cost": [10, 20, 40]},
	"extra_resources": {"type": SCAVENGER, "max_level": 5, "bonus_per_level": 0.15, "cost": [15, 30, 60, 120, 240]},
	"inventory_slots": {"type": SCAVENGER, "max_level": 4, "bonus_per_level": 5, "cost": [25, 50, 100, 200]}
}

# Player.gd
var skill_points: int = 0
var skills: Dictionary = {}  # skill_id -> level

func add_xp(amount: int):
	xp += amount
	while xp >= _xp_for_next_level():
		level += 1
		skill_points += 1
		xp -= _xp_for_next_level()

func unlock_skill(skill_id: String) -> bool:
	var skill = SkillData.SKILLS[skill_id]
	var current_level = skills.get(skill_id, 0)
	
	if current_level >= skill.max_level:
		return false
	
	var cost = skill.cost[current_level]
	if skill_points < cost:
		return false
	
	skill_points -= cost
	skills[skill_id] = current_level + 1
	_apply_skill_bonuses()
	return true

func _apply_skill_bonuses():
	# Recalculate all bonuses
	max_health = GameConstants.PLAYER_MAX_HEALTH + (skills.get("max_health", 0) * 20.0)
	damage_multiplier = 1.0 + (skills.get("damage_boost", 0) * 0.1)
	# ... etc
```

---

# Status Effects

```gdscript
# entities/StatusEffect.gd
class_name StatusEffect

enum Type { BLEED, POISON, SLOW, RADIATION }

var type: Type
var duration: float
var tick_rate: float
var damage_per_tick: float
var movement_multiplier: float = 1.0

# Player.gd
var active_effects: Array[StatusEffect] = []

func apply_status(effect: StatusEffect):
	active_effects.append(effect)

func _tick_status_effects(delta: float):
	for effect in active_effects:
		effect.duration -= delta
		effect.tick_rate -= delta
		
		if effect.tick_rate <= 0:
			match effect.type:
				StatusEffect.Type.BLEED:
					take_damage(effect.damage_per_tick)
				StatusEffect.Type.POISON:
					take_damage(effect.damage_per_tick * 0.5)
				StatusEffect.Type.RADIATION:
					take_damage(effect.damage_per_tick * 2.0)
			
			effect.tick_rate = 1.0  # Reset tick
		
		if effect.duration <= 0:
			active_effects.erase(effect)

func get_movement_multiplier() -> float:
	var mult = 1.0
	for effect in active_effects:
		if effect.type == StatusEffect.Type.SLOW:
			mult *= effect.movement_multiplier
	return mult
```

---

# Crafting & Workbench

```gdscript
# entities/Workbench.gd
class_name Workbench extends NetworkedEntity

enum Tier { BASIC, ADVANCED, EXPERT }

var tier: Tier = Tier.BASIC
var owner_id: int = 0

const TIER_UNLOCKS = {
	Tier.BASIC: ["pistol", "rifle", "wood_wall"],
	Tier.ADVANCED: ["shotgun", "smg", "stone_wall", "medkit"],
	Tier.EXPERT: ["sniper", "metal_wall", "explosives"]
}

# shared/CraftingRecipes.gd
const RECIPES = {
	"rifle": {
		"tier": Workbench.Tier.BASIC,
		"cost": [{"item_id": "metal_fragments", "qty": 50}, {"item_id": "wood", "qty": 200}],
		"craft_time": 10.0
	},
	"medkit": {
		"tier": Workbench.Tier.ADVANCED,
		"cost": [{"item_id": "cloth", "qty": 15}, {"item_id": "medical_supplies", "qty": 3}],
		"craft_time": 5.0
	}
}

# Research system
var researched_items: Array[String] = []

func research_item(item_id: String, player: Player) -> bool:
	if item_id in researched_items:
		return false
	
	# Consume one of the item
	if player.inventory.remove_item(item_id, 1):
		researched_items.append(item_id)
		return true
	return false
```

---

# NPC Traders

```gdscript
# entities/Trader.gd
class_name Trader extends NetworkedEntity

var trader_id: String = "general_goods"
var reputation_required: float = 0.0
var stock: Array[Dictionary] = []  # [{item_id, price, qty}]
var restock_timer: float = 0.0

const RESTOCK_INTERVAL = 3600.0  # 1 hour

func _physics_process(delta):
	restock_timer -= delta
	if restock_timer <= 0:
		_restock()
		restock_timer = RESTOCK_INTERVAL

func _restock():
	stock = TraderData.STOCK_TABLES[trader_id].roll_stock()

func try_buy(player: Player, item_id: String) -> bool:
	if player.reputation < reputation_required:
		return false
	
	for entry in stock:
		if entry.item_id == item_id and entry.qty > 0:
			if player.currency >= entry.price:
				player.currency -= entry.price
				player.inventory.add_item(item_id, 1)
				entry.qty -= 1
				return true
	return false

func try_sell(player: Player, item_id: String) -> bool:
	var sell_price = TraderData.SELL_PRICES.get(item_id, 0) * 0.7  # 70% of buy price
	
	if player.inventory.remove_item(item_id, 1):
		player.currency += sell_price
		return true
	return false
```

---

# Territory Control

```gdscript
# entities/ControlPoint.gd
class_name ControlPoint extends NetworkedEntity

var controlling_team: int = 0  # 0 = neutral
var capture_progress: float = 0.0
var resource_spawn_timer: float = 0.0

const CAPTURE_RADIUS = 200.0
const CAPTURE_RATE = 0.1  # Per second per player
const RESOURCE_SPAWN_INTERVAL = 300.0  # 5 min

func _physics_process(delta):
	if not is_authority():
		return
	
	var nearby_players = _get_players_in_radius()
	var dominant_team = _get_dominant_team(nearby_players)
	
	if dominant_team > 0 and dominant_team != controlling_team:
		capture_progress += CAPTURE_RATE * nearby_players[dominant_team] * delta
		
		if capture_progress >= 100.0:
			controlling_team = dominant_team
			capture_progress = 0.0
			_on_captured()
	else:
		capture_progress = max(0.0, capture_progress - (CAPTURE_RATE * delta))
	
	# Spawn resources
	if controlling_team > 0:
		resource_spawn_timer -= delta
		if resource_spawn_timer <= 0:
			_spawn_zone_resources()
			resource_spawn_timer = RESOURCE_SPAWN_INTERVAL

const ZONE_BONUSES = {
	"craft_speed": 1.5,  # 50% faster crafting
	"loot_mult": 1.3     # 30% more loot
}
```

---

# Weather & Day-Night

```gdscript
# systems/TimeSystem.gd (autoload)
var current_time: float = 0.0  # 0-86400 (24 hours)
var time_scale: float = 60.0   # 1 real min = 1 game hour

const DAY_START = 21600.0   # 6 AM
const NIGHT_START = 72000.0  # 8 PM

func _process(delta):
	current_time += delta * time_scale
	if current_time >= 86400.0:
		current_time -= 86400.0
	
	_update_lighting()

func is_night() -> bool:
	return current_time >= NIGHT_START or current_time < DAY_START

func _update_lighting():
	var light_level = 1.0
	if is_night():
		light_level = 0.3
	
	RenderingServer.global_shader_parameter_set("ambient_light", light_level)

# ServerMain.gd - Night modifiers
func _spawn_enemy_wave():
	var count = 4
	if TimeSystem.is_night():
		count = 8  # 2x enemies at night
	
	for i in range(count):
		_spawn_enemy(_get_random_spawn())

# Weather system
enum Weather { CLEAR, RAIN, FOG }

var current_weather: Weather = Weather.CLEAR
var visibility_range: float = 1000.0

func _update_weather():
	match current_weather:
		Weather.RAIN:
			visibility_range = 600.0
			player_speed_mult = 0.9
		Weather.FOG:
			visibility_range = 300.0
```

---

# Vehicle System

```gdscript
# entities/Vehicle.gd
class_name Vehicle extends NetworkedEntity

enum Type { BIKE, CAR, TRUCK }

var vehicle_type: Type = Type.BIKE
var driver_id: int = 0
var fuel: float = 100.0
var health: float = 500.0
var storage: Inventory

const SPEEDS = {
	Type.BIKE: 400.0,
	Type.CAR: 300.0,
	Type.TRUCK: 200.0
}

const STORAGE_SLOTS = {
	Type.BIKE: 5,
	Type.CAR: 10,
	Type.TRUCK: 30
}

func try_enter(player: Player) -> bool:
	if driver_id > 0:
		return false  # Occupied
	
	driver_id = player.net_id
	player.in_vehicle = self
	return true

func try_exit(player: Player):
	if driver_id == player.net_id:
		driver_id = 0
		player.in_vehicle = null
		player.global_position = global_position + Vector2(50, 0)  # Exit to side

# Player.gd
var in_vehicle: Vehicle = null

func apply_input(mv, aim, buttons, dt):
	if in_vehicle:
		# Vehicle movement
		in_vehicle.global_position += mv.normalized() * SPEEDS[in_vehicle.vehicle_type] * dt
		in_vehicle.rotation = mv.angle()
		
		# Exit vehicle
		if buttons & BTN_EXIT_VEHICLE:
			in_vehicle.try_exit(self)
	else:
		# Normal movement
		...
```

---

# Building Plan System

```gdscript
# client/BuildingMode.gd
class_name BuildingMode extends Node

var active: bool = false
var selected_structure: StructureType = StructureType.WALL
var preview_ghost: Node2D
var rotation: int = 0

func _input(event):
	if Input.is_action_just_pressed("build_mode"):  # B key
		active = !active
		preview_ghost.visible = active
	
	if active:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_1: selected_structure = StructureType.WALL
				KEY_2: selected_structure = StructureType.FOUNDATION
				KEY_3: selected_structure = StructureType.DOORWAY
				KEY_R: rotation = (rotation + 90) % 360

func _process(_delta):
	if not active:
		return
	
	var mouse_pos = get_global_mouse_position()
	var cupboard = _find_nearest_cupboard(mouse_pos)
	
	if cupboard:
		var snapped = BuildingGrid.snap_to_grid(mouse_pos, cupboard.global_position)
		preview_ghost.global_position = snapped
		preview_ghost.rotation_degrees = rotation
		
		# Color based on validity
		var can_place = _can_place_at(snapped, cupboard)
		preview_ghost.modulate = Color.GREEN if can_place else Color.RED
	
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_confirm_placement()
```

---

## Implementation Priority

1. **Status Effects** (foundation for combat depth)
2. **Crafting/Workbench** (enables progression)
3. **Skill Tree** (long-term goals)
4. **NPC Traders** (loot economy sink)
5. **Territory Control** (endgame PvP objective)
6. **Day-Night** (atmosphere + risk/reward)
7. **Vehicles** (large map traversal)
