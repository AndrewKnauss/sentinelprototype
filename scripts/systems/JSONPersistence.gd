# JSON-based persistence backend for prototyping
# Fast to implement, no dependencies, human-readable
extends PersistenceBackend
class_name JSONPersistence

const SAVE_DIR = "user://saves"
const PLAYERS_DIR = "user://saves/players"
const INVENTORY_DIR = "user://saves/inventory"
const STRUCTURES_FILE = "user://saves/structures.json"

var _structures_cache: Array = []  # In-memory cache
var _next_structure_id: int = 1

# ========== INITIALIZATION ==========
func initialize() -> void:
	# Create directories
	DirAccess.make_dir_recursive_absolute(PLAYERS_DIR)
	DirAccess.make_dir_recursive_absolute(INVENTORY_DIR)
	
	# Load structures into memory
	if FileAccess.file_exists(STRUCTURES_FILE):
		var file = FileAccess.open(STRUCTURES_FILE, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(json_text)
			
			if parse_result == OK:
				var data = json.data
				if data is Dictionary:
					_structures_cache = data.get("structures", [])
					_next_structure_id = data.get("next_id", 1)
			else:
				push_error("Failed to parse structures.json: " + json.get_error_message())
	else:
		_save_structures_to_disk()
	
	print("[JSONPersistence] Initialized: %d structures loaded" % _structures_cache.size())

# ========== PLAYER METHODS ==========
func load_player(username: String) -> Dictionary:
	var path = "%s/%s.json" % [PLAYERS_DIR, username.to_lower()]
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open player file: " + path)
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result == OK:
		var data = json.data
		return data if data is Dictionary else {}
	else:
		push_error("Failed to parse player JSON: " + json.get_error_message())
		return {}

func save_player(player_data: Dictionary) -> void:
	var username = player_data.get("username", "")
	if username.is_empty():
		push_error("Invalid username in player_data")
		return
	
	var path = "%s/%s.json" % [PLAYERS_DIR, username.to_lower()]
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open player file for writing: " + path)
		return
	
	file.store_string(JSON.stringify(player_data, "\t"))
	file.close()

func delete_player(username: String) -> void:
	var path = "%s/%s.json" % [PLAYERS_DIR, username.to_lower()]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	
	# Also delete inventory
	var inv_path = "%s/%s.json" % [INVENTORY_DIR, username.to_lower()]
	if FileAccess.file_exists(inv_path):
		DirAccess.remove_absolute(inv_path)

func wipe_all_players() -> void:
	_wipe_directory(PLAYERS_DIR)
	_wipe_directory(INVENTORY_DIR)
	print("[JSONPersistence] All player data wiped")

func get_all_player_usernames() -> Array:
	var usernames = []
	var dir = DirAccess.open(PLAYERS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var username = file_name.trim_suffix(".json")
				usernames.append(username)
			file_name = dir.get_next()
		dir.list_dir_end()
	return usernames

func is_username_taken(username: String) -> bool:
	var path = "%s/%s.json" % [PLAYERS_DIR, username.to_lower()]
	return FileAccess.file_exists(path)

# ========== INVENTORY METHODS ==========
func load_inventory(username: String) -> Array:
	var path = "%s/%s.json" % [INVENTORY_DIR, username.to_lower()]
	if not FileAccess.file_exists(path):
		return []
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open inventory file: " + path)
		return []
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result == OK:
		var data = json.data
		if data is Dictionary:
			return data.get("slots", [])
	else:
		push_error("Failed to parse inventory JSON: " + json.get_error_message())
	
	return []

func save_inventory(username: String, slots: Array) -> void:
	var path = "%s/%s.json" % [INVENTORY_DIR, username.to_lower()]
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open inventory file for writing: " + path)
		return
	
	file.store_string(JSON.stringify({"slots": slots}, "\t"))
	file.close()

# ========== STRUCTURE METHODS ==========
func load_all_structures() -> Array:
	return _structures_cache.duplicate()

func save_structure(structure_data: Dictionary) -> int:
	var new_structure = structure_data.duplicate()
	new_structure["id"] = _next_structure_id
	_next_structure_id += 1
	
	_structures_cache.append(new_structure)
	_save_structures_to_disk()
	
	return new_structure["id"]

func update_structure(structure_id: int, structure_data: Dictionary) -> void:
	for i in range(_structures_cache.size()):
		if _structures_cache[i].get("id") == structure_id:
			# Merge updates but preserve ID
			_structures_cache[i].merge(structure_data)
			_structures_cache[i]["id"] = structure_id
			_save_structures_to_disk()
			return

func delete_structure(structure_id: int) -> void:
	for i in range(_structures_cache.size()):
		if _structures_cache[i].get("id") == structure_id:
			_structures_cache.remove_at(i)
			_save_structures_to_disk()
			return

func wipe_all_structures() -> void:
	_structures_cache.clear()
	_next_structure_id = 1
	_save_structures_to_disk()
	print("[JSONPersistence] All structures wiped")

func get_stats() -> Dictionary:
	return {
		"players": get_all_player_usernames().size(),
		"structures": _structures_cache.size()
	}

# ========== HELPERS ==========
func _save_structures_to_disk() -> void:
	var file = FileAccess.open(STRUCTURES_FILE, FileAccess.WRITE)
	if not file:
		push_error("Failed to open structures file for writing")
		return
	
	var data = {
		"structures": _structures_cache,
		"next_id": _next_structure_id
	}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _wipe_directory(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
