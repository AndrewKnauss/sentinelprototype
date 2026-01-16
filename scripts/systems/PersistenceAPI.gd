# Persistence API - Abstraction layer for save/load systems
# Autoload name: "Persistence"
# Allows swapping backends (JSON -> SQLite) without changing game code
extends Node

var _backend: PersistenceBackend

func _ready():
	# Phase 1: JSON for prototyping (no dependencies, human-readable)
	_backend = JSONPersistence.new()
	
	# Phase 2: Migrate to SQLite when needed (50+ players or performance issues)
	# _backend = SQLitePersistence.new()
	
	_backend.initialize()
	print("[Persistence] Backend initialized: %s" % _backend.get_script().resource_path.get_file())

# ========== PLAYER API ==========
func load_player(username: String) -> Dictionary:
	return _backend.load_player(username)

func save_player(player_data: Dictionary) -> void:
	_backend.save_player(player_data)

func delete_player(username: String) -> void:
	_backend.delete_player(username)

func wipe_all_players() -> void:
	_backend.wipe_all_players()

func get_all_player_usernames() -> Array:
	return _backend.get_all_player_usernames()

func is_username_taken(username: String) -> bool:
	return _backend.is_username_taken(username)

# ========== INVENTORY API ==========
func load_inventory(username: String) -> Array:
	return _backend.load_inventory(username)

func save_inventory(username: String, slots: Array) -> void:
	_backend.save_inventory(username, slots)

# ========== STRUCTURE API ==========
func load_all_structures() -> Array:
	return _backend.load_all_structures()

func save_structure(structure_data: Dictionary) -> int:
	return _backend.save_structure(structure_data)

func update_structure(structure_id: int, structure_data: Dictionary) -> void:
	_backend.update_structure(structure_id, structure_data)

func delete_structure(structure_id: int) -> void:
	_backend.delete_structure(structure_id)

func wipe_all_structures() -> void:
	_backend.wipe_all_structures()

# ========== ADMIN API ==========
func get_stats() -> Dictionary:
	return _backend.get_stats()
