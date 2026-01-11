# Loot System

## Overview
Item drops from enemies/world events, pickup interaction, inventory management, and drop-on-death mechanics.

## Architecture

### Entity: ItemDrop (extends NetworkedEntity)
**Purpose**: Physical loot item in the world  
**Authority**: Server-only spawns, clients interpolate  
**Replication**: Position, item type, rarity, quantity

### Data Structures
```gdscript
# Item definition (shared/ItemData.gd)
class_name ItemData
const TYPE_WEAPON = 0
const TYPE_AMMO = 1
const TYPE_RESOURCE = 2
const TYPE_CONSUMABLE = 3

var id: String          # "rifle", "scrap_metal", "medkit"
var type: int           # TYPE_*
var name: String        # Display name
var icon: Texture2D     # UI icon
var stack_size: int     # Max stack (1 for weapons, 999 for resources)
var rarity: int         # 0=common, 1=uncommon, 2=rare, 3=epic

# Loot table (server-only)
class_name LootTable
var items: Array[Dictionary] = []  # [{item_id, weight, min_qty, max_qty}]

func roll() -> Dictionary:
	# Weighted random selection
	var total_weight = 0
	for entry in items:
		total_weight += entry.weight
	
	var roll = randf() * total_weight
	var current = 0.0
	for entry in items:
		current += entry.weight
		if roll < current:
			return {
				"id": entry.item_id,
				"qty": randi_range(entry.min_qty, entry.max_qty)
			}
	return {}
```

### Server Workflow
```gdscript
# ServerMain.gd
var _item_drops: Array[ItemDrop] = []

func _on_enemy_died(enemy: Enemy):
	var loot = ENEMY_LOOT_TABLE.roll()
	if loot.is_empty():
		return
	
	_spawn_item_drop(enemy.global_position, loot.id, loot.qty)

func _spawn_item_drop(pos: Vector2, item_id: String, qty: int):
	var drop = ItemDrop.new()
	drop.net_id = Replication.generate_id()
	drop.authority = 1
	drop.global_position = pos
	drop.item_id = item_id
	drop.quantity = qty
	_world.add_child(drop)
	_item_drops.append(drop)
	
	Net.spawn_entity.rpc({
		"type": "item_drop",
		"net_id": drop.net_id,
		"pos": pos,
		"extra": {"item_id": item_id, "qty": qty}
	})

func _try_pickup_item(player: Player, drop: ItemDrop):
	# Check range
	if player.global_position.distance_to(drop.global_position) > 50:
		return
	
	# Add to inventory (returns remaining qty if full)
	var remaining = player.inventory.add_item(drop.item_id, drop.quantity)
	
	if remaining == 0:
		# Fully picked up
		Net.despawn_entity.rpc(drop.net_id)
		drop.queue_free()
		_item_drops.erase(drop)
	else:
		# Partial pickup
		drop.quantity = remaining
		# Sync updated quantity to clients
		...
```

### Client Interaction
```gdscript
# ClientMain.gd - Input handling
func _physics_process(delta):
	...
	if Input.is_action_just_pressed("ui_interact"):  # E key
		_try_pickup_nearest_item()

func _try_pickup_nearest_item():
	var player = _players.get(_my_id)
	if not player:
		return
	
	# Find nearest item drop
	var nearest: ItemDrop = null
	var nearest_dist = 50.0  # Max pickup range
	
	for entity in Replication.get_all_entities():
		if entity is ItemDrop:
			var dist = player.global_position.distance_to(entity.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = entity
	
	if nearest:
		# Send pickup request to server
		Net.server_request_pickup.rpc_id(1, nearest.net_id)
```

### Inventory Component
```gdscript
# entities/Inventory.gd (attached to Player)
class_name Inventory

const MAX_SLOTS = 20

var slots: Array[Dictionary] = []  # [{item_id, qty}]

func _ready():
	slots.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		slots[i] = {"item_id": "", "qty": 0}

func add_item(item_id: String, qty: int) -> int:
	# Try to stack into existing slots
	for slot in slots:
		if slot.item_id == item_id:
			var item_def = ItemRegistry.get(item_id)
			var space = item_def.stack_size - slot.qty
			if space > 0:
				var to_add = min(qty, space)
				slot.qty += to_add
				qty -= to_add
				if qty == 0:
					return 0
	
	# Fill empty slots
	for slot in slots:
		if slot.item_id == "":
			slot.item_id = item_id
			var item_def = ItemRegistry.get(item_id)
			var to_add = min(qty, item_def.stack_size)
			slot.qty = to_add
			qty -= to_add
			if qty == 0:
				return 0
	
	return qty  # Remaining if inventory full

func get_replicated_state() -> Dictionary:
	return {"slots": slots}
```

## Implementation Steps

1. **Create ItemData + ItemRegistry** (shared constants)
2. **Add Inventory to Player** (component with add/remove)
3. **Create ItemDrop entity** (visual + collision)
4. **Add loot tables** (enemy drops, world spawns)
5. **Implement pickup** (E key interaction)
6. **Add drop-on-death** (server-side on player kill)
7. **Create inventory UI** (grid display with drag/drop)

## Integration Points

### Enemy.gd Changes
```gdscript
# Add signal
signal dropped_loot(items: Array[Dictionary])

func take_damage(amount, attacker_id):
	health -= amount
	if health <= 0:
		# Roll loot before dying
		var loot = ENEMY_LOOT_TABLE.roll()
		dropped_loot.emit([loot])  # Array for multiple items
		died.emit(net_id)
		return true
```

### Player.gd Changes
```gdscript
var inventory: Inventory

func _ready():
	...
	inventory = Inventory.new()
	add_child(inventory)

func take_damage(amount):
	...
	if health <= 0:
		drop_all_items.emit(inventory.get_all_items())
		...
```

## Testing Checklist
- [ ] Items spawn on enemy death
- [ ] Items are pickupable within range
- [ ] Inventory stacking works correctly
- [ ] Full inventory prevents pickup
- [ ] Items drop on player death
- [ ] Network sync (all clients see drops)
- [ ] Items persist on client reconnect

## Potential Issues

**Problem**: Item duplication on lag  
**Solution**: Server validates all pickups, clients request only

**Problem**: Item drops through floor  
**Solution**: Raycast spawn position down to ground

**Problem**: Too many items lag server  
**Solution**: Despawn timer (5 min), merge nearby stacks
