# Persistence System

## Overview
Abstracted save/load system for player data, inventory, and structures. Designed with a clean API to allow swapping between JSON (prototype) and SQLite (production) implementations without touching game code.

## Architecture

### Abstraction Layer (PersistenceAPI)
```gdscript
# scripts/systems/PersistenceAPI.gd (autoload: "Persistence")
class_name PersistenceAPI extends Node

# Backend implementation (swappable)
var _backend: PersistenceBackend

func _ready():
	# Choose implementation based on config or development phase
	# Phase 1: JSON for fast prototyping
	_backend = JSONPersistence.new()
	
	# Phase 2: SQLite for production
	# _backend = SQLitePersistence.new()
	
	_backend.initialize()

# ========== PLAYER API ==========
func load_player(peer_id: int) -> Dictionary:
	return _backend.load_player(peer_id)

func save_player(player_data: Dictionary) -> void:
	_backend.save_player(player_data)

func delete_player(peer_id: int) -> void:
	_backend.delete_player(peer_id)

func wipe_all_players() -> void:
	_backend.wipe_all_players()

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
func get_all_player_ids() -> Array:
	return _backend.get_all_player_ids()

func get_stats() -> Dictionary:
	return _backend.get_stats()
```

### Backend Interface
```gdscript
# scripts/systems/PersistenceBackend.gd (abstract base class)
class_name PersistenceBackend extends RefCounted

# Override in implementations
func initialize() -> void:
	pass

func load_player(peer_id: int) -> Dictionary:
	return {}

func save_player(player_data: Dictionary) -> void:
	pass

func delete_player(peer_id: int) -> void:
	pass

func wipe_all_players() -> void:
	pass

func load_inventory(peer_id: int) -> Array:
	return []

func save_inventory(peer_id: int, slots: Array) -> void:
	pass

func load_all_structures() -> Array:
	return []

func save_structure(structure_data: Dictionary) -> int:
	return -1  # Return structure_id

func update_structure(structure_id: int, structure_data: Dictionary) -> void:
	pass

func delete_structure(structure_id: int) -> void:
	pass

func wipe_all_structures() -> void:
	pass

func get_all_player_ids() -> Array:
	return []

func get_stats() -> Dictionary:
	return {"players": 0, "structures": 0}
```

## Phase 1: JSON Implementation (Prototype)

### Pros
- **Zero dependencies** - No plugins needed
- **Human-readable** - Easy debugging
- **Fast to implement** - Can prototype today
- **File-based** - Works on all platforms

### Cons
- No concurrent write safety
- Slower for large datasets (1000+ players)
- No query optimization
- Manual file locking required

### File Structure
```
user://saves/
├── players/
│   ├── 12345.json  # peer_id.json
│   ├── 67890.json
│   └── ...
├── inventory/
│   ├── 12345.json  # peer_id.json
│   └── ...
└── structures.json  # All structures in one file
```

### Implementation
```gdscript
# scripts/systems/JSONPersistence.gd
class_name JSONPersistence extends PersistenceBackend

const SAVE_DIR = "user://saves"
const PLAYERS_DIR = "user://saves/players"
const INVENTORY_DIR = "user://saves/inventory"
const STRUCTURES_FILE = "user://saves/structures.json"

var _structures_cache: Array = []  # In-memory cache
var _next_structure_id: int = 1

func initialize() -> void:
	DirAccess.make_dir_recursive_absolute(PLAYERS_DIR)
	DirAccess.make_dir_recursive_absolute(INVENTORY_DIR)
	
	# Load structures into memory
	if FileAccess.file_exists(STRUCTURES_FILE):
		var file = FileAccess.open(STRUCTURES_FILE, FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		if data != null:
			_structures_cache = data.get("structures", [])
			_next_structure_id = data.get("next_id", 1)
		file.close()
	else:
		_save_structures_to_disk()

# ========== PLAYER METHODS ==========
func load_player(peer_id: int) -> Dictionary:
	var path = "%s/%d.json" % [PLAYERS_DIR, peer_id]
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	return data if data != null else {}

func save_player(player_data: Dictionary) -> void:
	var peer_id = player_data.get("peer_id", -1)
	if peer_id < 0:
		push_error("Invalid peer_id in player_data")
		return
	
	var path = "%s/%d.json" % [PLAYERS_DIR, peer_id]
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(player_data, "\t"))
	file.close()

func delete_player(peer_id: int) -> void:
	var path = "%s/%d.json" % [PLAYERS_DIR, peer_id]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	
	# Also delete inventory
	var inv_path = "%s/%d.json" % [INVENTORY_DIR, peer_id]
	if FileAccess.file_exists(inv_path):
		DirAccess.remove_absolute(inv_path)

func wipe_all_players() -> void:
	_wipe_directory(PLAYERS_DIR)
	_wipe_directory(INVENTORY_DIR)

func get_all_player_ids() -> Array:
	var ids = []
	var dir = DirAccess.open(PLAYERS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var peer_id = file_name.trim_suffix(".json").to_int()
				ids.append(peer_id)
			file_name = dir.get_next()
		dir.list_dir_end()
	return ids

# ========== INVENTORY METHODS ==========
func load_inventory(peer_id: int) -> Array:
	var path = "%s/%d.json" % [INVENTORY_DIR, peer_id]
	if not FileAccess.file_exists(path):
		return []
	
	var file = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	return data.get("slots", []) if data != null else []

func save_inventory(peer_id: int, slots: Array) -> void:
	var path = "%s/%d.json" % [INVENTORY_DIR, peer_id]
	var file = FileAccess.open(path, FileAccess.WRITE)
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

func get_stats() -> Dictionary:
	return {
		"players": get_all_player_ids().size(),
		"structures": _structures_cache.size()
	}

# ========== HELPERS ==========
func _save_structures_to_disk() -> void:
	var file = FileAccess.open(STRUCTURES_FILE, FileAccess.WRITE)
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
```

## Phase 2: SQLite Implementation (Production)

### When to Migrate
- 50+ concurrent players
- Need transaction safety
- Want backup/restore tools
- Performance becomes bottleneck

### Required Plugin
**godot-sqlite** (https://github.com/2shady4u/godot-sqlite)
- Maintained for Godot 4.x
- Installation: Add to `addons/` folder

### Schema
```sql
CREATE TABLE players (
    peer_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    position_x REAL DEFAULT 500.0,
    position_y REAL DEFAULT 300.0,
    health REAL DEFAULT 100.0,
    level INTEGER DEFAULT 1,
    xp INTEGER DEFAULT 0,
    reputation REAL DEFAULT 0.0,
    currency INTEGER DEFAULT 0,
    last_login INTEGER,
    created_at INTEGER
);

CREATE TABLE inventory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    slot_index INTEGER NOT NULL,
    item_id TEXT NOT NULL,
    quantity INTEGER DEFAULT 1,
    is_hot BOOLEAN DEFAULT 0,
    hot_timer REAL DEFAULT 0.0,
    FOREIGN KEY (peer_id) REFERENCES players(peer_id),
    UNIQUE(peer_id, slot_index)
);

CREATE TABLE structures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id INTEGER NOT NULL,
    type TEXT NOT NULL,
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    health REAL DEFAULT 100.0,
    created_at INTEGER,
    FOREIGN KEY (owner_id) REFERENCES players(peer_id)
);

CREATE INDEX idx_structures_owner ON structures(owner_id);
CREATE INDEX idx_inventory_peer ON inventory(peer_id);
```

### Implementation Stub
```gdscript
# scripts/systems/SQLitePersistence.gd
class_name SQLitePersistence extends PersistenceBackend

var _db: SQLite

func initialize() -> void:
	_db = SQLite.new()
	_db.path = "user://sentinel.db"
	_db.open_db()
	_create_tables()

func _create_tables() -> void:
	# ... SQL schema creation
	pass

# Implement all PersistenceBackend methods using _db.query() ...
```

## Server Integration

### Player Login
```gdscript
# ServerMain.gd
func _on_peer_connected(peer_id: int):
	Log.network("Player %d connecting, loading data..." % peer_id)
	
	# Load player data
	var data = Persistence.load_player(peer_id)
	
	var player = Player.new()
	player.net_id = peer_id
	player.authority = 1
	
	if data.is_empty():
		# NEW PLAYER - Default spawn
		player.global_position = _get_random_spawn()
		player.player_name = "Player_%d" % peer_id
		player.health = GameConstants.PLAYER_MAX_HEALTH
		player.level = 1
		player.xp = 0
		player.reputation = 0.0
		player.currency = 0
		
		Log.network("New player %d created" % peer_id)
	else:
		# RETURNING PLAYER - Restore state
		player.global_position = Vector2(data.position_x, data.position_y)
		player.player_name = data.get("name", "Player_%d" % peer_id)
		player.health = data.get("health", 100.0)
		player.level = data.get("level", 1)
		player.xp = data.get("xp", 0)
		player.reputation = data.get("reputation", 0.0)
		player.currency = data.get("currency", 0)
		
		Log.network("Loaded player %d: pos=%s, hp=%.1f, level=%d" % [
			peer_id, player.global_position, player.health, player.level
		])
	
	_world.add_child(player)
	_players[peer_id] = player
	
	# Load inventory (if system exists)
	# var inv_slots = Persistence.load_inventory(peer_id)
	# player.inventory.load_from_array(inv_slots)
	
	# Initial save (creates DB entry if new)
	_save_player(player)

func _save_player(player: Player) -> void:
	var data = {
		"peer_id": player.net_id,
		"name": player.player_name,
		"position_x": player.global_position.x,
		"position_y": player.global_position.y,
		"health": player.health,
		"level": player.level,
		"xp": player.xp,
		"reputation": player.reputation,
		"currency": player.currency,
		"last_login": Time.get_unix_time_from_system()
	}
	Persistence.save_player(data)
```

### Disconnect Save
```gdscript
# ServerMain.gd
func _on_peer_disconnected(peer_id: int):
	if _players.has(peer_id):
		var player = _players[peer_id]
		
		# SAVE ON DISCONNECT
		_save_player(player)
		
		# Save inventory (if system exists)
		# Persistence.save_inventory(player.net_id, player.inventory.get_slots())
		
		Log.network("Saved player %d on disconnect" % peer_id)
		
		player.queue_free()
		_players.erase(peer_id)
```

### Autosave (Every 30 Seconds)
```gdscript
# ServerMain.gd
var _autosave_timer: float = 0.0
const AUTOSAVE_INTERVAL = 30.0  # Prototype: 30s for easy testing

func _physics_process(delta):
	# ... existing simulation code
	
	# AUTOSAVE TIMER
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		_autosave_all()

func _autosave_all():
	Log.network("Autosave started...")
	
	# Save all players
	for peer_id in _players:
		var player = _players[peer_id]
		_save_player(player)
		# Persistence.save_inventory(peer_id, player.inventory.get_slots())
	
	# Save all structures
	for wall in _walls:
		_save_or_update_structure(wall)
	
	Log.network("Autosaved %d players, %d structures" % [_players.size(), _walls.size()])

func _save_or_update_structure(wall: Wall):
	var structure_id = wall.get_meta("structure_id", -1)
	
	var data = {
		"owner_id": wall.builder_id,
		"type": "wall",
		"position_x": wall.global_position.x,
		"position_y": wall.global_position.y,
		"health": wall.health,
		"created_at": Time.get_unix_time_from_system()
	}
	
	if structure_id < 0:
		# New structure - save and store ID
		structure_id = Persistence.save_structure(data)
		wall.set_meta("structure_id", structure_id)
	else:
		# Existing structure - update
		Persistence.update_structure(structure_id, data)
```

### Structure Loading
```gdscript
# ServerMain.gd
func _ready():
	# ... existing setup
	
	if Net.is_server():
		_load_all_structures()

func _load_all_structures():
	var structures = Persistence.load_all_structures()
	
	Log.network("Loading %d structures from database..." % structures.size())
	
	for data in structures:
		match data.get("type", ""):
			"wall":
				_spawn_persisted_wall(data)

func _spawn_persisted_wall(data: Dictionary):
	var wall = Wall.new()
	wall.net_id = Replication.generate_id()
	wall.authority = 1
	wall.global_position = Vector2(data.position_x, data.position_y)
	wall.health = data.get("health", 100.0)
	wall.builder_id = data.get("owner_id", -1)
	wall.set_meta("structure_id", data.get("id", -1))
	wall.destroyed.connect(_on_wall_destroyed)
	
	_world.add_child(wall)
	_walls.append(wall)

func _on_wall_destroyed(wall: Wall):
	var structure_id = wall.get_meta("structure_id", -1)
	if structure_id >= 0:
		Persistence.delete_structure(structure_id)
	
	_walls.erase(wall)
	Replication.despawn_entity(wall.net_id)
	wall.queue_free()
```

## Admin Commands

### Server Console Commands
```gdscript
# ServerMain.gd
func _input(event: InputEvent):
	if not Net.is_server():
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F5:
				_admin_wipe_structures()
			KEY_F6:
				_admin_wipe_players()
			KEY_F7:
				_admin_show_stats()

func _admin_wipe_structures():
	Log.warn("ADMIN: Wiping all structures...")
	
	# Delete in-memory
	for wall in _walls:
		wall.queue_free()
	_walls.clear()
	
	# Delete from database
	Persistence.wipe_all_structures()
	
	Log.warn("ADMIN: All structures wiped")

func _admin_wipe_players():
	Log.warn("ADMIN: Wiping all player data...")
	
	# Disconnect all players
	for peer_id in _players.keys():
		_players[peer_id].queue_free()
	_players.clear()
	
	# Delete from database
	Persistence.wipe_all_players()
	
	Log.warn("ADMIN: All player data wiped")

func _admin_show_stats():
	var stats = Persistence.get_stats()
	Log.network("=== PERSISTENCE STATS ===")
	Log.network("Players in DB: %d" % stats.players)
	Log.network("Structures in DB: %d" % stats.structures)
	Log.network("Players online: %d" % _players.size())
	Log.network("Walls spawned: %d" % _walls.size())
	Log.network("========================")
```

### In-Game Admin Panel (Future)
```gdscript
# Could add RPC-based admin UI accessible from client
# For now, server console commands are sufficient
```

## Graceful Shutdown

```gdscript
# Bootstrap.gd (server)
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if Net.is_server():
			_shutdown_server()
		get_tree().quit()

func _shutdown_server():
	Log.network("Server shutting down, saving all data...")
	
	# Force immediate save of all players
	for peer_id in ServerMain._players:
		var player = ServerMain._players[peer_id]
		ServerMain._save_player(player)
		# Persistence.save_inventory(peer_id, player.inventory.get_slots())
	
	# Force save of all structures
	for wall in ServerMain._walls:
		ServerMain._save_or_update_structure(wall)
	
	Log.network("Shutdown save complete: %d players, %d structures" % [
		ServerMain._players.size(),
		ServerMain._walls.size()
	])
```

## Implementation Checklist

### Phase 1: JSON Backend (This Session)
- [ ] Create `scripts/systems/PersistenceBackend.gd` (abstract)
- [ ] Create `scripts/systems/PersistenceAPI.gd` (autoload)
- [ ] Create `scripts/systems/JSONPersistence.gd` (implementation)
- [ ] Add player save/load in `ServerMain._on_peer_connected`
- [ ] Add disconnect save in `ServerMain._on_peer_disconnected`
- [ ] Add 30-second autosave timer
- [ ] Add structure loading in `ServerMain._ready`
- [ ] Add structure save on build
- [ ] Add structure delete on destroy
- [ ] Add admin commands (F5/F6/F7)
- [ ] Add graceful shutdown handler
- [ ] **Test**: New player spawns with defaults
- [ ] **Test**: Disconnect and reconnect preserves position
- [ ] **Test**: Structures survive server restart
- [ ] **Test**: Autosave triggers every 30s
- [ ] **Test**: F5/F6 wipe commands work

### Phase 2: SQLite Migration (Future Session)
- [ ] Install `godot-sqlite` plugin
- [ ] Create `scripts/systems/SQLitePersistence.gd`
- [ ] Implement schema creation
- [ ] Implement all backend methods
- [ ] Switch `PersistenceAPI._backend` to SQLite
- [ ] Test migration from JSON files
- [ ] Performance test with 100+ players

## Testing Plan

### Manual Testing
1. Start server
2. Connect 2 clients
3. Move around, build walls
4. **Disconnect 1 client** → Check save message in logs
5. Wait 30s → Check autosave message
6. **Reconnect client** → Verify position restored
7. Press F7 → Check stats match
8. **Restart server** → Verify walls still exist
9. Press F5 → Verify all walls deleted
10. Reconnect client → Verify player data still exists
11. Press F6 → Verify player data wiped

### Edge Cases
- Multiple disconnects within autosave window
- Structure deletion during autosave
- Server crash (kill process) → Verify last autosave persists
- Empty database → Verify fresh player creation

## Performance Notes

### JSON Backend
- **Read**: O(1) for player data (single file)
- **Write**: O(1) for player data (single file)
- **Structure load**: O(n) at server start (all structures)
- **Autosave**: O(n) players + O(1) structures (single file)

**Expected bottleneck**: Autosaving 100+ players (100 file writes = ~50-100ms)

### SQLite Backend
- **Read**: O(log n) with indexes
- **Write**: O(log n) with transaction batching
- **Autosave**: Single transaction = ~10ms for 1000 players

**Migration trigger**: When JSON autosave exceeds 100ms

## Data Format Examples

### Player JSON
```json
{
	"peer_id": 12345,
	"name": "Player_12345",
	"position_x": 512.5,
	"position_y": 384.2,
	"health": 85.0,
	"level": 5,
	"xp": 450,
	"reputation": 120.5,
	"currency": 250,
	"last_login": 1704844800
}
```

### Inventory JSON
```json
{
	"slots": [
		{"item_id": "wood", "qty": 50, "is_hot": false, "hot_timer": 0.0},
		{"item_id": "metal", "qty": 20, "is_hot": true, "hot_timer": 142.5},
		{"item_id": "", "qty": 0, "is_hot": false, "hot_timer": 0.0}
	]
}
```

### Structures JSON
```json
{
	"structures": [
		{
			"id": 1,
			"owner_id": 12345,
			"type": "wall",
			"position_x": 600.0,
			"position_y": 400.0,
			"health": 100.0,
			"created_at": 1704844800
		}
	],
	"next_id": 2
}
```
