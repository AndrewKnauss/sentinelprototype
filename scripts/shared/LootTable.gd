extends RefCounted
class_name LootTable

# =============================================================================
# LootTable.gd - Weighted Random Loot Generation
# =============================================================================
# Defines loot tables for enemies, world events, containers
# =============================================================================

# Loot entry: {item_id: String, weight: float, min_qty: int, max_qty: int}
var entries: Array = []


func add_entry(item_id: String, weight: float, min_qty: int = 1, max_qty: int = 1):
	entries.append({
		"item_id": item_id,
		"weight": weight,
		"min_qty": min_qty,
		"max_qty": max_qty
	})


# Roll for a random item (returns {item_id, quantity} or empty dict)
func roll() -> Dictionary:
	if entries.is_empty():
		return {}
	
	# Calculate total weight
	var total_weight = 0.0
	for entry in entries:
		total_weight += entry.weight
	
	# Random roll
	var roll = randf() * total_weight
	var current = 0.0
	
	for entry in entries:
		current += entry.weight
		if roll < current:
			return {
				"item_id": entry.item_id,
				"quantity": randi_range(entry.min_qty, entry.max_qty)
			}
	
	# Fallback (shouldn't happen)
	return {}


# Roll multiple items (for bosses/events)
func roll_multiple(count: int) -> Array:
	var results = []
	for i in range(count):
		var loot = roll()
		if not loot.is_empty():
			results.append(loot)
	return results
