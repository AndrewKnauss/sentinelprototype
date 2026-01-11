# Base Building System

## Overview
Rust-inspired base building with tool cupboard ownership, grid-snapped placement (local to cupboard), decay/upkeep, and raiding mechanics.

## Core Concepts

**Tool Cupboard** = Ownership claim + upkeep container  
**Building Grid** = Local to cupboard, not world-global  
**Decay** = Structures lose health without upkeep  
**Raiding** = Destructible cupboard transfers ownership

---

## Tool Cupboard

### Entity Definition
```gdscript
# entities/ToolCupboard.gd
class_name ToolCupboard extends NetworkedEntity

signal ownership_transferred(old_owner: int, new_owner: int)
signal upkeep_depleted()

var owner_id: int = 0
var authorized_ids: Array[int] = []  # Can build/modify
var claim_radius: float = 30.0 * 32  # 30 tiles (~960 units)
var health: float = 500.0
var upkeep_storage: Dictionary = {}  # item_id -> quantity
var decay_timer: float = 0.0

const DECAY_START_DELAY = 86400.0  # 24 hours before decay starts
const HEALTH_DECAY_RATE = 1.0  # HP per hour without upkeep
```

### Placement Rules
```gdscript
# ServerMain.gd
func _try_place_cupboard(player: Player, pos: Vector2) -> bool:
	# Check if position is already claimed
	for cupboard in _cupboards:
		if cupboard.global_position.distance_to(pos) < cupboard.claim_radius:
			Net.client_show_notification.rpc_id(player.net_id, {
				"type": "build_blocked",
				"message": "Too close to another base"
			})
			return false
	
	# Check build cost
	if not player.inventory.has_items([
		{"id": "wood", "qty": 1000},
		{"id": "metal_fragments", "qty": 100}
	]):
		return false
	
	# Consume materials
	player.inventory.remove_items([...])
	
	# Spawn cupboard
	var cupboard = ToolCupboard.new()
	cupboard.net_id = Replication.generate_id()
	cupboard.authority = 1
	cupboard.global_position = pos
	cupboard.owner_id = player.net_id
	cupboard.authorized_ids = [player.net_id]
	cupboard.destroyed.connect(_on_cupboard_destroyed)
	_world.add_child(cupboard)
	_cupboards.append(cupboard)
	
	Database.save_cupboard(cupboard)
	return true
```

### Authorization System
```gdscript
# ToolCupboard.gd
func is_authorized(peer_id: int) -> bool:
	return peer_id == owner_id or peer_id in authorized_ids

func add_authorized(peer_id: int):
	if not peer_id in authorized_ids:
		authorized_ids.append(peer_id)

func remove_authorized(peer_id: int):
	authorized_ids.erase(peer_id)

# ServerMain.gd
func _can_build_at(player: Player, pos: Vector2) -> ToolCupboard:
	# Find cupboard claiming this position
	for cupboard in _cupboards:
		if cupboard.global_position.distance_to(pos) < cupboard.claim_radius:
			# Check authorization
			if cupboard.is_authorized(player.net_id):
				return cupboard
			else:
				return null  # Blocked by enemy cupboard
	
	# No cupboard = can't build (outside all bases)
	return null
```

---

## Building Grid System

### Grid Coordinates (Local to Cupboard)
```gdscript
# shared/BuildingGrid.gd
class_name BuildingGrid

const GRID_SIZE = 32.0  # Unit size (matches wall size)

static func world_to_grid(world_pos: Vector2, cupboard_pos: Vector2) -> Vector2i:
	var local = world_pos - cupboard_pos
	return Vector2i(
		int(round(local.x / GRID_SIZE)),
		int(round(local.y / GRID_SIZE))
	)

static func grid_to_world(grid_pos: Vector2i, cupboard_pos: Vector2) -> Vector2:
	return cupboard_pos + Vector2(
		grid_pos.x * GRID_SIZE,
		grid_pos.y * GRID_SIZE
	)

static func snap_to_grid(world_pos: Vector2, cupboard_pos: Vector2) -> Vector2:
	var grid = world_to_grid(world_pos, cupboard_pos)
	return grid_to_world(grid, cupboard_pos)
```

### Structure Types
```gdscript
# shared/StructureData.gd
enum StructureType {
	FOUNDATION,  # Floor piece
	WALL,        # Vertical wall
	DOORWAY,     # Wall with door frame
	WINDOW,      # Wall with window
	STAIRS,      # Vertical transition
	ROOF         # Top cover
}

class_name StructureDefinition
var type: StructureType
var name: String
var health: float
var build_cost: Array[Dictionary]  # [{item_id, qty}]
var grid_size: Vector2i  # Footprint (1x1 for wall, 2x1 for doorway, etc)
var tier: int  # 0=wood, 1=stone, 2=metal, 3=armored

const DEFINITIONS = {
	StructureType.WALL: StructureDefinition.new(
		StructureType.WALL,
		"Wall",
		250.0,
		[{"item_id": "wood", "qty": 300}],
		Vector2i(1, 1),
		0
	),
	# ... more definitions
}
```

### Placement System
```gdscript
# ServerMain.gd
func _try_place_structure(player: Player, type: StructureType, pos: Vector2, rotation: int):
	# Find cupboard
	var cupboard = _can_build_at(player, pos)
	if not cupboard:
		return
	
	# Snap to cupboard's grid
	var snapped_pos = BuildingGrid.snap_to_grid(pos, cupboard.global_position)
	var grid_pos = BuildingGrid.world_to_grid(snapped_pos, cupboard.global_position)
	
	# Check if grid cell occupied
	if cupboard.is_grid_occupied(grid_pos):
		return
	
	# Check build cost
	var def = StructureData.DEFINITIONS[type]
	if not player.inventory.has_items(def.build_cost):
		return
	
	# Consume materials
	player.inventory.remove_items(def.build_cost)
	
	# Spawn structure
	var structure = _create_structure(type, snapped_pos, rotation)
	structure.cupboard_id = cupboard.net_id
	structure.grid_pos = grid_pos
	cupboard.register_structure(grid_pos, structure)
	
	Database.save_structure(structure)
```

### Cupboard Grid Tracking
```gdscript
# ToolCupboard.gd
var grid_structures: Dictionary = {}  # Vector2i -> Structure

func is_grid_occupied(grid_pos: Vector2i) -> bool:
	return grid_structures.has(grid_pos)

func register_structure(grid_pos: Vector2i, structure: Structure):
	grid_structures[grid_pos] = structure

func unregister_structure(grid_pos: Vector2i):
	grid_structures.erase(grid_pos)
```

---

## Decay & Upkeep

### Resource Storage
```gdscript
# ToolCupboard.gd
const UPKEEP_ITEMS = ["wood", "stone", "metal_fragments", "high_quality_metal"]
const MAX_UPKEEP_STORAGE = 10000  # Per resource type

func add_upkeep(item_id: String, qty: int) -> int:
	if not item_id in UPKEEP_ITEMS:
		return qty  # Not accepted
	
	var current = upkeep_storage.get(item_id, 0)
	var space = MAX_UPKEEP_STORAGE - current
	var to_add = min(qty, space)
	
	upkeep_storage[item_id] = current + to_add
	return qty - to_add  # Remaining

func consume_upkeep(costs: Dictionary) -> bool:
	# Check if have enough
	for item_id in costs:
		if upkeep_storage.get(item_id, 0) < costs[item_id]:
			return false
	
	# Consume
	for item_id in costs:
		upkeep_storage[item_id] -= costs[item_id]
	
	return true
```

### Decay Calculation
```gdscript
# ServerMain.gd
const DECAY_CHECK_INTERVAL = 3600.0  # 1 hour

func _physics_process(delta):
	# ... existing code
	_tick_base_decay(delta)

func _tick_base_decay(delta: float):
	for cupboard in _cupboards:
		cupboard.decay_timer += delta
		
		if cupboard.decay_timer >= DECAY_CHECK_INTERVAL:
			cupboard.decay_timer = 0.0
			_process_base_decay(cupboard)

func _process_base_decay(cupboard: ToolCupboard):
	# Calculate upkeep cost
	var total_cost = _calculate_upkeep_cost(cupboard)
	
	# Try to consume
	if cupboard.consume_upkeep(total_cost):
		# Upkeep paid, no decay
		return
	
	# No upkeep - apply decay to all structures
	upkeep_depleted.emit()
	
	for structure in cupboard.grid_structures.values():
		structure.health -= ToolCupboard.HEALTH_DECAY_RATE
		
		if structure.health <= 0:
			_destroy_structure(structure)

func _calculate_upkeep_cost(cupboard: ToolCupboard) -> Dictionary:
	var costs = {}
	
	for structure in cupboard.grid_structures.values():
		var def = StructureData.DEFINITIONS[structure.type]
		
		# Upkeep = 10% of build cost per day
		for item in def.build_cost:
			var daily_cost = int(item.qty * 0.1)
			costs[item.item_id] = costs.get(item.item_id, 0) + daily_cost
	
	return costs
```

### UI Display
```gdscript
# client/CupboardUI.gd
func update_upkeep_display(cupboard: ToolCupboard):
	var total_cost = _calculate_upkeep_cost(cupboard)
	var time_remaining = _calculate_time_remaining(cupboard, total_cost)
	
	_upkeep_label.text = "Upkeep: %dh remaining" % int(time_remaining / 3600.0)
	
	for item_id in total_cost:
		var stored = cupboard.upkeep_storage.get(item_id, 0)
		var needed = total_cost[item_id]
		_item_labels[item_id].text = "%d / %d" % [stored, needed]
```

---

## Raiding & Ownership Transfer

### Cupboard Destruction
```gdscript
# ServerMain.gd
func _on_cupboard_destroyed(cupboard: ToolCupboard):
	# Cupboard destroyed = base becomes "raidable"
	# Next player to place cupboard nearby claims it
	
	# Mark all structures as "unclaimed"
	for structure in cupboard.grid_structures.values():
		structure.is_unclaimed = true
		structure.modulate = Color(1, 0.5, 0.5, 0.8)  # Visual indicator
	
	# Remove cupboard
	Database.delete_cupboard(cupboard.net_id)
	cupboard.queue_free()
	_cupboards.erase(cupboard)

func _try_place_cupboard(player: Player, pos: Vector2) -> bool:
	# ... existing checks
	
	# Check for nearby unclaimed structures
	var claimed_structures: Array[Structure] = []
	
	for structure in _get_all_structures():
		if structure.is_unclaimed and structure.global_position.distance_to(pos) < cupboard.claim_radius:
			claimed_structures.append(structure)
	
	if not claimed_structures.is_empty():
		# Claiming existing base
		for structure in claimed_structures:
			structure.is_unclaimed = false
			structure.cupboard_id = cupboard.net_id
			structure.modulate = Color.WHITE
			cupboard.register_structure(structure.grid_pos, structure)
		
		Net.client_show_notification.rpc_id(player.net_id, {
			"type": "base_claimed",
			"message": "Claimed %d structures" % claimed_structures.size()
		})
```

### Soft-Side Exploit Prevention
```gdscript
# entities/Structure.gd
var facing: Vector2 = Vector2.RIGHT  # Direction structure faces
var is_soft_side: bool = false

func take_damage(amount: float, hit_from: Vector2) -> bool:
	# Determine if hit from soft side (inside base)
	var to_hit = (hit_from - global_position).normalized()
	var dot = facing.dot(to_hit)
	
	is_soft_side = dot > 0  # Hit from inside
	
	# Soft side takes more damage
	var multiplier = 3.0 if is_soft_side else 1.0
	health -= amount * multiplier
	
	return health <= 0
```

---

## Building Rotation & Snapping

### Rotation System
```gdscript
# ClientMain.gd - Building mode
var _build_rotation: int = 0  # 0, 90, 180, 270

func _input(event):
	if _building_mode_active:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_R:
				_build_rotation = (_build_rotation + 90) % 360

func _show_build_preview(type: StructureType, mouse_pos: Vector2):
	var cupboard = _find_nearest_cupboard(mouse_pos)
	if not cupboard:
		return
	
	var snapped = BuildingGrid.snap_to_grid(mouse_pos, cupboard.global_position)
	
	_build_preview.global_position = snapped
	_build_preview.rotation_degrees = _build_rotation
	
	# Color preview based on validity
	var can_build = _can_build_at(snapped)
	_build_preview.modulate = Color.GREEN if can_build else Color.RED
```

### Socket Snapping (Walls to Foundations)
```gdscript
# shared/StructureData.gd
class_name StructureDefinition
var snap_points: Array[Vector2] = []  # Local offsets for connections

# Example: Foundation has 4 edge snap points
const FOUNDATION_SNAPS = [
	Vector2(16, 0),    # Right
	Vector2(-16, 0),   # Left
	Vector2(0, 16),    # Bottom
	Vector2(0, -16)    # Top
]

# ClientMain.gd
func _find_snap_position(mouse_pos: Vector2, type: StructureType) -> Vector2:
	# Find nearby structures
	for structure in _get_nearby_structures(mouse_pos, 64):
		var def = StructureData.DEFINITIONS[structure.type]
		
		# Check each snap point
		for snap in def.snap_points:
			var world_snap = structure.global_position + snap.rotated(structure.rotation)
			
			if mouse_pos.distance_to(world_snap) < 16:
				return world_snap  # Snap to socket
	
	# No snap found, use grid snap
	return BuildingGrid.snap_to_grid(mouse_pos, cupboard.global_position)
```

---

## Building Tiers & Upgrades

### Tier System
```gdscript
enum Tier { WOOD, STONE, METAL, ARMORED }

const TIER_HEALTH = {
	Tier.WOOD: 250.0,
	Tier.STONE: 500.0,
	Tier.METAL: 1000.0,
	Tier.ARMORED: 2000.0
}

const TIER_UPGRADE_COST = {
	Tier.WOOD: [],  # Can't downgrade
	Tier.STONE: [{"item_id": "stone", "qty": 300}],
	Tier.METAL: [{"item_id": "metal_fragments", "qty": 200}],
	Tier.ARMORED: [{"item_id": "high_quality_metal", "qty": 25}]
}
```

### Upgrade Interaction
```gdscript
# ServerMain.gd
func _try_upgrade_structure(player: Player, structure: Structure):
	if structure.tier >= Tier.ARMORED:
		return  # Max tier
	
	var next_tier = structure.tier + 1
	var cost = TIER_UPGRADE_COST[next_tier]
	
	if not player.inventory.has_items(cost):
		return
	
	player.inventory.remove_items(cost)
	
	structure.tier = next_tier
	structure.health = TIER_HEALTH[next_tier]
	structure.update_visual()
	
	Database.update_structure(structure)
```

---

## Implementation Steps

1. Create ToolCupboard entity
2. Add authorization system
3. Implement BuildingGrid (local snap)
4. Create StructureDefinitions
5. Add placement validation
6. Implement upkeep/decay
7. Add raiding mechanics
8. Create building UI
9. Add tier upgrade system
10. Persistence integration

---

## Database Schema

```sql
CREATE TABLE cupboards (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id INTEGER NOT NULL,
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    health REAL DEFAULT 500.0,
    authorized_ids TEXT,  -- JSON array
    upkeep_storage TEXT,  -- JSON dict
    decay_timer REAL DEFAULT 0.0,
    FOREIGN KEY (owner_id) REFERENCES players(peer_id)
);

CREATE TABLE structures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cupboard_id INTEGER,  -- NULL if unclaimed
    owner_id INTEGER NOT NULL,
    type INTEGER NOT NULL,  -- StructureType enum
    tier INTEGER DEFAULT 0,
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    grid_x INTEGER NOT NULL,  -- Local grid coords
    grid_y INTEGER NOT NULL,
    rotation INTEGER DEFAULT 0,
    health REAL DEFAULT 250.0,
    is_unclaimed BOOLEAN DEFAULT 0,
    FOREIGN KEY (cupboard_id) REFERENCES cupboards(id),
    FOREIGN KEY (owner_id) REFERENCES players(peer_id)
);
```

---

## Balance Values

```gdscript
const CUPBOARD_HEALTH = 500.0
const CUPBOARD_CLAIM_RADIUS = 960.0  # 30 tiles
const CUPBOARD_PLACEMENT_MIN_DIST = 1920.0  # 60 tiles between bases
const DECAY_START_DELAY = 86400.0  # 24 hours
const DECAY_CHECK_INTERVAL = 3600.0  # 1 hour
const UPKEEP_RATE = 0.1  # 10% of build cost per day
const SOFT_SIDE_MULTIPLIER = 3.0
```

---

## Edge Cases

**Problem**: Player builds, leaves server, base decays  
**Solution**: 24h grace period before decay starts

**Problem**: Griefing via blocking cupboard placement  
**Solution**: Minimum distance between cupboards (60 tiles)

**Problem**: Cupboard spam to claim large area  
**Solution**: Upkeep cost scales with structure count

**Problem**: Offline raiding (no defense)  
**Solution**: Longer decay on raided bases (48h grace for owner to return)

---

## Testing Checklist

- [ ] Cupboard placement validates distance
- [ ] Grid snaps locally to cupboard
- [ ] Authorization prevents enemy building
- [ ] Upkeep consumption works
- [ ] Decay applies correctly
- [ ] Structures become unclaimed on cupboard destruction
- [ ] Soft-side damage multiplier applies
- [ ] Tier upgrades persist
- [ ] Socket snapping feels good
- [ ] Rotation cycles properly
