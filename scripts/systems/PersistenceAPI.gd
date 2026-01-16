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
func load_player(peer_id: int) -> Dictionary:
	return _backend.load_player(peer_id)

func save_player(player_data: Dictionary) -> void:
	_backend.save_player(player_data)

func delete_player(peer_id: int) -> void:
	_backend.delete_player(peer_id)

func wipe_all_players() -> void:
	_backend.wipe_all_players()

func get_all_player_ids() -> Array:
	return _backend.get_all_player_ids()

# ========== INVENTORY API ==========
func load_inventory(peer_id: int) -> Array:
	return _backend.load_inventory(peer_id)

func save_inventory(peer_id: int, slots: Array) -> void:
	_backend.save_inventory(peer_id, slots)

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
