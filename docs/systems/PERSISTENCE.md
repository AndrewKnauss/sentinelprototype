# Persistence System

## Overview
Database-backed save system for player data, inventory, and base structures. Essential foundation for all progression systems.

## Database Choice

**Recommendation: SQLite** (for prototype/indie scale)  
- File-based (easy deployment)
- No external dependencies
- Railway.app supports mounted volumes
- Good for <1000 concurrent players

**Alternative: PostgreSQL** (if scaling beyond indie)
- Railway.app has built-in Postgres
- Better concurrent write performance
- Requires connection pooling

## Schema

```sql
-- players table
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
    last_login INTEGER,  -- Unix timestamp
    created_at INTEGER
);

-- inventory table
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

-- structures table (walls, turrets, etc)
CREATE TABLE structures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id INTEGER NOT NULL,
    type TEXT NOT NULL,  -- 'wall', 'turret', etc
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    health REAL DEFAULT 100.0,
    created_at INTEGER,
    FOREIGN KEY (owner_id) REFERENCES players(peer_id)
);

-- bounties table
CREATE TABLE bounties (
    target_id INTEGER PRIMARY KEY,
    value INTEGER DEFAULT 100,
    kill_count INTEGER DEFAULT 1,
    last_kill_time INTEGER,
    FOREIGN KEY (target_id) REFERENCES players(peer_id)
);

CREATE INDEX idx_structures_owner ON structures(owner_id);
CREATE INDEX idx_inventory_peer ON inventory(peer_id);
```

## Database Wrapper

```gdscript
# systems/Database.gd (autoload)
class_name Database extends Node

var db: SQLite

func _ready():
	db = SQLite.new()
	
	if not db.open("user://sentinel.db"):
		push_error("Failed to open database")
		return
	
	_create_tables()

func _create_tables():
	db.query("""
		CREATE TABLE IF NOT EXISTS players (
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
		)
	""")
	
	db.query("""
		CREATE TABLE IF NOT EXISTS inventory (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			peer_id INTEGER NOT NULL,
			slot_index INTEGER NOT NULL,
			item_id TEXT NOT NULL,
			quantity INTEGER DEFAULT 1,
			is_hot BOOLEAN DEFAULT 0,
			hot_timer REAL DEFAULT 0.0,
			FOREIGN KEY (peer_id) REFERENCES players(peer_id),
			UNIQUE(peer_id, slot_index)
		)
	""")
	
	db.query("""
		CREATE TABLE IF NOT EXISTS structures (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			owner_id INTEGER NOT NULL,
			type TEXT NOT NULL,
			position_x REAL NOT NULL,
			position_y REAL NOT NULL,
			health REAL DEFAULT 100.0,
			created_at INTEGER,
			FOREIGN KEY (owner_id) REFERENCES players(peer_id)
		)
	""")

# Player data methods
func load_player(peer_id: int) -> Dictionary:
	var result = db.select_rows("players", "peer_id = %d" % peer_id, ["*"])
	return result[0] if not result.is_empty() else {}

func save_player(player: Player):
	var data = {
		"peer_id": player.net_id,
		"name": player.name,
		"position_x": player.global_position.x,
		"position_y": player.global_position.y,
		"health": player.health,
		"level": player.level,
		"xp": player.xp,
		"reputation": player.reputation,
		"currency": player.currency,
		"last_login": Time.get_unix_time_from_system()
	}
	
	# Upsert (insert or update)
	var existing = load_player(player.net_id)
	if existing.is_empty():
		data["created_at"] = Time.get_unix_time_from_system()
		db.insert_row("players", data)
	else:
		db.update_rows("players", "peer_id = %d" % player.net_id, data)

# Inventory methods
func load_inventory(peer_id: int) -> Array:
	return db.select_rows("inventory", "peer_id = %d" % peer_id, ["*"])

func save_inventory(player: Player):
	# Clear existing
	db.delete_rows("inventory", "peer_id = %d" % player.net_id)
	
	# Insert all non-empty slots
	for i in range(player.inventory.slots.size()):
		var slot = player.inventory.slots[i]
		if slot.item_id != "":
			db.insert_row("inventory", {
				"peer_id": player.net_id,
				"slot_index": i,
				"item_id": slot.item_id,
				"quantity": slot.qty,
				"is_hot": slot.is_hot,
				"hot_timer": slot.hot_timer
			})

# Structure methods
func load_structures(owner_id: int = -1) -> Array:
	if owner_id < 0:
		return db.select_rows("structures", "", ["*"])
	else:
		return db.select_rows("structures", "owner_id = %d" % owner_id, ["*"])

func save_structure(wall: Wall):
	db.insert_row("structures", {
		"owner_id": wall.builder_id,
		"type": "wall",
		"position_x": wall.global_position.x,
		"position_y": wall.global_position.y,
		"health": wall.health,
		"created_at": Time.get_unix_time_from_system()
	})

func delete_structure(structure_id: int):
	db.delete_rows("structures", "id = %d" % structure_id)
```

## Server Integration

```gdscript
# ServerMain.gd
func _on_peer_connected(peer_id: int):
	# Load player data
	var data = Database.load_player(peer_id)
	
	var player = Player.new()
	player.net_id = peer_id
	player.authority = 1
	
	if data.is_empty():
		# New player
		player.global_position = _get_random_spawn()
		player.name = "Player_%d" % peer_id
		player.level = 1
		player.xp = 0
	else:
		# Returning player
		player.global_position = Vector2(data.position_x, data.position_y)
		player.health = data.health
		player.level = data.level
		player.xp = data.xp
		player.reputation = data.reputation
		player.currency = data.currency
	
	_world.add_child(player)
	_players[peer_id] = player
	
	# Load inventory
	_load_player_inventory(player)
	
	# Save initial state
	Database.save_player(player)

func _load_player_inventory(player: Player):
	var inv_data = Database.load_inventory(player.net_id)
	
	for row in inv_data:
		var slot_idx = row.slot_index
		player.inventory.slots[slot_idx] = {
			"item_id": row.item_id,
			"qty": row.quantity,
			"is_hot": bool(row.is_hot),
			"hot_timer": row.hot_timer
		}

func _on_peer_disconnected(peer_id: int):
	if _players.has(peer_id):
		var player = _players[peer_id]
		
		# Save before disconnect
		Database.save_player(player)
		Database.save_inventory(player)
		
		player.queue_free()
		_players.erase(peer_id)

# Auto-save every 5 minutes
var _save_timer: float = 0.0
const AUTOSAVE_INTERVAL = 300.0

func _physics_process(delta):
	# ... existing code
	
	_save_timer += delta
	if _save_timer >= AUTOSAVE_INTERVAL:
		_save_timer = 0.0
		_autosave_all()

func _autosave_all():
	for peer_id in _players:
		var player = _players[peer_id]
		Database.save_player(player)
		Database.save_inventory(player)
	
	Log.network("Autosaved %d players" % _players.size())
```

## Structure Persistence

```gdscript
# ServerMain.gd
func _ready():
	# ... existing code
	_load_all_structures()

func _load_all_structures():
	var structures = Database.load_structures()
	
	for row in structures:
		match row.type:
			"wall":
				_spawn_persisted_wall(row)

func _spawn_persisted_wall(data: Dictionary):
	var wall = Wall.new()
	wall.net_id = Replication.generate_id()
	wall.authority = 1
	wall.global_position = Vector2(data.position_x, data.position_y)
	wall.health = data.health
	wall.builder_id = data.owner_id
	wall.set_meta("db_id", data.id)  # Track DB row
	wall.destroyed.connect(_on_wall_destroyed)
	_world.add_child(wall)
	_walls.append(wall)

func _try_build_wall(player: Player, aim_dir: Vector2):
	# ... existing spawn code
	
	# Save to database
	Database.save_structure(wall)
	var db_id = Database.db.last_insert_rowid
	wall.set_meta("db_id", db_id)

func _on_wall_destroyed(wall: Wall):
	var db_id = wall.get_meta("db_id", -1)
	if db_id >= 0:
		Database.delete_structure(db_id)
	
	# ... existing despawn code
```

## Graceful Shutdown

```gdscript
# Bootstrap.gd (server)
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_server()
		get_tree().quit()

func _shutdown_server():
	if not Net.is_server():
		return
	
	Log.network("Server shutting down, saving all data...")
	
	# Save all players
	for peer_id in ServerMain._players:
		var player = ServerMain._players[peer_id]
		Database.save_player(player)
		Database.save_inventory(player)
	
	# Close database
	Database.db.close()
	
	Log.network("Shutdown complete")
```

## Implementation Steps

1. Add SQLite plugin to project (GDExtension)
2. Create Database autoload
3. Define schema + create_tables
4. Implement save/load for Player
5. Implement save/load for Inventory
6. Implement save/load for Structures
7. Add autosave timer
8. Add graceful shutdown handler

## Testing Checklist
- [ ] New players spawn with defaults
- [ ] Returning players load saved position/stats
- [ ] Inventory persists across sessions
- [ ] Structures remain after server restart
- [ ] Autosave triggers every 5 minutes
- [ ] Graceful shutdown saves all data
- [ ] Database doesn't corrupt on crash

## Potential Issues

**Problem**: Database locks on concurrent writes  
**Solution**: Queue writes, process sequentially in main thread

**Problem**: Save corruption on crash  
**Solution**: WAL mode + periodic integrity checks

**Problem**: Large player count slows autosave  
**Solution**: Stagger saves over 5s window instead of instant
