extends Node
class_name Inventory

# =============================================================================
# Inventory.gd - Player Inventory Component
# =============================================================================
# Manages player item storage with stacking, adding, removing
# Attached to Player as a child node
# =============================================================================

const MAX_SLOTS: int = 20

# Slot structure: {item_id: String, quantity: int}
var slots: Array = []

signal inventory_changed()


func _ready() -> void:
	# Initialize empty slots
	slots.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		slots[i] = {"item_id": "", "quantity": 0}


# Add item to inventory, returns remaining quantity if full
func add_item(item_id: String, quantity: int) -> int:
	if not ItemRegistry.exists(item_id):
		push_error("Invalid item_id: %s" % item_id)
		return quantity
	
	var item_def = ItemRegistry.get_item(item_id)
	var remaining = quantity
	
	# First pass: stack into existing slots
	for slot in slots:
		if slot.item_id == item_id:
			var space = item_def.stack_size - slot.quantity
			if space > 0:
				var to_add = min(remaining, space)
				slot.quantity += to_add
				remaining -= to_add
				if remaining == 0:
					inventory_changed.emit()
					return 0
	
	# Second pass: fill empty slots
	for slot in slots:
		if slot.item_id == "":
			slot.item_id = item_id
			var to_add = min(remaining, item_def.stack_size)
			slot.quantity = to_add
			remaining -= to_add
			if remaining == 0:
				inventory_changed.emit()
				return 0
	
	# Inventory full, return remaining
	if remaining < quantity:
		inventory_changed.emit()
	return remaining


# Remove item from inventory, returns true if successful
func remove_item(item_id: String, quantity: int) -> bool:
	var remaining = quantity
	
	# Remove from slots (reverse order to avoid index issues)
	for i in range(slots.size() - 1, -1, -1):
		var slot = slots[i]
		if slot.item_id == item_id:
			var to_remove = min(remaining, slot.quantity)
			slot.quantity -= to_remove
			remaining -= to_remove
			
			# Clear slot if empty
			if slot.quantity == 0:
				slot.item_id = ""
			
			if remaining == 0:
				inventory_changed.emit()
				return true
	
	# Not enough items
	return false


# Check if inventory has enough of an item
func has_item(item_id: String, quantity: int) -> bool:
	var count = 0
	for slot in slots:
		if slot.item_id == item_id:
			count += slot.quantity
			if count >= quantity:
				return true
	return false


# Get total count of an item
func get_item_count(item_id: String) -> int:
	var count = 0
	for slot in slots:
		if slot.item_id == item_id:
			count += slot.quantity
	return count


# Get all items (for drop-on-death)
func get_all_items() -> Array:
	var items = []
	for slot in slots:
		if slot.item_id != "":
			items.append({"item_id": slot.item_id, "quantity": slot.quantity})
	return items


# Clear all items
func clear():
	for slot in slots:
		slot.item_id = ""
		slot.quantity = 0
	inventory_changed.emit()


# Get replicated state for network sync
func get_replicated_state() -> Dictionary:
	return {"slots": slots.duplicate(true)}


# Apply replicated state from network
func apply_replicated_state(state: Dictionary):
	if state.has("slots"):
		slots = state.slots.duplicate(true)
		inventory_changed.emit()
