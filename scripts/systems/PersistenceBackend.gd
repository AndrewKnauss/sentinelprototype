# Abstract base class for persistence backends
# Subclasses implement actual storage (JSON, SQLite, etc)
class_name PersistenceBackend extends RefCounted

# ========== INITIALIZATION ==========
func initialize() -> void:
	push_error("PersistenceBackend.initialize() not implemented")

# ========== PLAYER API ==========
func load_player(username: String) -> Dictionary:
	push_error("PersistenceBackend.load_player() not implemented")
	return {}

func save_player(player_data: Dictionary) -> void:
	push_error("PersistenceBackend.save_player() not implemented")

func delete_player(username: String) -> void:
	push_error("PersistenceBackend.delete_player() not implemented")

func wipe_all_players() -> void:
	push_error("PersistenceBackend.wipe_all_players() not implemented")

func get_all_player_usernames() -> Array:
	push_error("PersistenceBackend.get_all_player_usernames() not implemented")
	return []

func is_username_taken(username: String) -> bool:
	push_error("PersistenceBackend.is_username_taken() not implemented")
	return false

# ========== INVENTORY API ==========
func load_inventory(username: String) -> Array:
	push_error("PersistenceBackend.load_inventory() not implemented")
	return []

func save_inventory(username: String, slots: Array) -> void:
	push_error("PersistenceBackend.save_inventory() not implemented")

# ========== STRUCTURE API ==========
func load_all_structures() -> Array:
	push_error("PersistenceBackend.load_all_structures() not implemented")
	return []

func save_structure(structure_data: Dictionary) -> int:
	push_error("PersistenceBackend.save_structure() not implemented")
	return -1

func update_structure(structure_id: int, structure_data: Dictionary) -> void:
	push_error("PersistenceBackend.update_structure() not implemented")

func delete_structure(structure_id: int) -> void:
	push_error("PersistenceBackend.delete_structure() not implemented")

func wipe_all_structures() -> void:
	push_error("PersistenceBackend.wipe_all_structures() not implemented")

# ========== ADMIN API ==========
func get_stats() -> Dictionary:
	push_error("PersistenceBackend.get_stats() not implemented")
	return {"players": 0, "structures": 0}
