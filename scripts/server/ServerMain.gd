extends Node2D
class_name ServerMain

# =============================================================================
# ServerMain.gd
# =============================================================================
# Authoritative server with players, enemies, bullets, and walls.
# =============================================================================

var _world: Node2D
var _players: Dictionary = {}  # peer_id -> Player
var _enemies: Array = []  # Array of Enemy
var _walls: Array = []  # Array of Wall
var _bullets: Array = []  # Array of Bullet

var _last_input: Dictionary = {}  # peer_id -> cmd
var _last_seq: Dictionary = {}  # peer_id -> int
var _server_tick: int = 0
var _static_snapshot_timer: float = 0.0
var _autosave_timer: float = 0.0

const ENEMY_SPAWN_POSITIONS = [
	Vector2(200, 200),
	Vector2(600, 200),
	Vector2(400, 400),
	Vector2(400, 450),
	Vector2(500, 500)
]
const STATIC_SNAPSHOT_INTERVAL: float = 5.0
const AUTOSAVE_INTERVAL: float = 30.0  # Autosave every 30 seconds


func _ready() -> void:
	randomize()
	
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	
	var title = Label.new()
	title.text = "SERVER"
	title.position = Vector2(10, 10)
	add_child(title)
	
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.input_received.connect(_on_input_received)
	
	# Load persisted structures
	_load_all_structures()
	
	# Spawn initial enemies
	for pos in ENEMY_SPAWN_POSITIONS:
		_spawn_enemy(pos)


func _physics_process(_delta: float) -> void:
	if not Net.is_server():
		return
	
	_server_tick += 1
	var dt = GameConstants.FIXED_DELTA
	
	# 1. Simulate all players
	for peer_id in _players:
		var player = _players[peer_id]
		var cmd = _last_input.get(peer_id, {})
		
		if not cmd.is_empty():
			var mv = cmd.get("mv", Vector2.ZERO)
			var aim = cmd.get("aim", Vector2.ZERO)
			var btn = cmd.get("btn", 0)
			
			player.apply_input(mv, aim, btn, dt)
			
			# Shooting
			if btn & GameConstants.BTN_SHOOT and player.shoot():
				# Get weapon damage
				var weapon_damage = GameConstants.BULLET_DAMAGE
				if player.equipped_weapon:
					weapon_damage = player.equipped_weapon.data.get("damage", GameConstants.BULLET_DAMAGE)
				
				# Spawn multiple pellets for shotguns
				var pellets = 1
				var spread = 0.0
				if player.equipped_weapon:
					pellets = player.equipped_weapon.data.get("pellets", 1)
					spread = player.equipped_weapon.data.get("spread", 0.0)
				
				for i in range(pellets):
					var spread_angle = randf_range(-spread, spread)
					var fire_dir = aim.rotated(spread_angle)
					_spawn_bullet(player.global_position, fire_dir, peer_id, weapon_damage)
			
			# Building
			if btn & GameConstants.BTN_BUILD:
				_try_build_wall(player, aim)
	
	# 2. Enemies simulate themselves in their _physics_process
	#    (AI, shooting, movement all handled by Enemy.gd)
	#    Just check if they want to shoot
	for enemy in _enemies:
		if enemy and is_instance_valid(enemy):
			# Enemy AI already runs in Enemy._physics_process
			# We just need to listen for when they decide to shoot
			# This is handled by checking enemy.shoot() in Enemy._ai_chase_and_shoot
			pass
	
	# 3. Clean up invalid bullets
	_cleanup_bullets()
	
	# 4. Replicate
	if not Net.get_peers().is_empty():
		var states = Replication.build_snapshot()
		
		# IMPORTANT: Wrap states in a sub-dictionary to avoid key type issues
		var snapshot = {
			"tick": _server_tick,
			"states": states
		}
		
		Net.client_receive_snapshot.rpc(snapshot)
		
		for peer_id in Net.get_peers():
			var ack = {
				"tick": _server_tick,
				"ack_seq": _last_seq.get(peer_id, 0)
			}
			Net.client_receive_ack.rpc_id(peer_id, ack)
	
	# 5. Send static snapshot periodically
	_static_snapshot_timer += dt
	if _static_snapshot_timer >= STATIC_SNAPSHOT_INTERVAL:
		_static_snapshot_timer = 0.0
		_send_static_snapshot()
	
	# 6. Autosave periodically
	_autosave_timer += dt
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		_autosave_all()


func _cleanup_bullets() -> void:
	"""Remove bullets that have been freed (collision detection happens in Bullet.gd)."""
	var bullets_to_remove = []
	
	for bullet in _bullets:
		if not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			bullets_to_remove.append(bullet)
	
	# Clean up list
	for bullet in bullets_to_remove:
		_bullets.erase(bullet)


func _spawn_bullet(pos: Vector2, dir: Vector2, owner: int, dmg: float = GameConstants.BULLET_DAMAGE) -> void:
	var bullet = Bullet.new()
	bullet.net_id = Replication.generate_id()
	bullet.authority = 1
	bullet.initialize(pos, dir.normalized(), owner, dmg)
	_world.add_child(bullet)
	_bullets.append(bullet)
	
	# Tell clients
	Net.spawn_entity.rpc({
		"type": "bullet",
		"net_id": bullet.net_id,
		"pos": pos,
		"extra": {"dir": dir.normalized(), "owner": owner, "damage": dmg}
	})


func _spawn_enemy(pos: Vector2, enemy_type: String = "") -> void:
	# Random type if not specified
	#if enemy_type.is_empty():
		
	var types = ["scout", "tank", "sniper", "swarm", "normal"]
	var weights = [0.25, 0.15, 0.50, 0.25, 0.2]  # Scout/Swarm more common
	enemy_type = _weighted_random(types, weights)
	
	var enemy: Enemy
	match enemy_type:
		"scout":
			enemy = EnemyScout.new()
		"tank":
			enemy = EnemyTank.new()
		"sniper":
			enemy = EnemySniper.new()
		"swarm":
			enemy = EnemySwarm.new()
		_:
			enemy = Enemy.new()
			enemy_type = "normal"
	
	enemy.net_id = Replication.generate_id()
	enemy.authority = 1
	enemy.global_position = pos
	enemy.died.connect(func(_id): _respawn_enemy(enemy, enemy_type))
	
	# Different damage for different types
	var damage = GameConstants.BULLET_DAMAGE
	if enemy is EnemyScout:
		damage = 15.0
	elif enemy is EnemyTank:
		damage = 35.0
	elif enemy is EnemySniper:
		damage = 60.0
	elif enemy is EnemySwarm:
		damage = 10.0
	
	enemy.wants_to_shoot.connect(func(dir): _spawn_bullet(enemy.global_position, dir, 0, damage))
	_world.add_child(enemy)
	_enemies.append(enemy)
	
	# Tell clients
	Net.spawn_entity.rpc({
		"type": "enemy",
		"net_id": enemy.net_id,
		"pos": pos,
		"extra": {"enemy_type": enemy_type}
	})


func _weighted_random(options: Array, weights: Array) -> String:
	var total = 0.0
	for w in weights:
		total += w
	
	var roll = randf() * total
	var cumulative = 0.0
	
	for i in range(options.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return options[i]
	
	return options[0]


func _respawn_enemy(enemy: Enemy, enemy_type: String) -> void:
	# Despawn
	Net.despawn_entity.rpc(enemy.net_id)
	enemy.queue_free()
	_enemies.erase(enemy)
	
	if _enemies.size() > 5:
		return
		
	# Respawn after delay (keep same type)
	await get_tree().create_timer(GameConstants.ENEMY_RESPAWN_TIME).timeout
	var spawn_pos = ENEMY_SPAWN_POSITIONS[randi() % ENEMY_SPAWN_POSITIONS.size()]
	_spawn_enemy(spawn_pos, enemy_type)


func _try_build_wall(player: Player, aim_dir: Vector2) -> void:
	# Place wall in front of player
	var wall_pos = player.global_position + aim_dir.normalized() * GameConstants.WALL_BUILD_RANGE
	
	# Snap to grid
	wall_pos.x = floor(wall_pos.x / GameConstants.WALL_SIZE_SIDE) * GameConstants.WALL_SIZE_SIDE + (GameConstants.WALL_SIZE_SIDE / 2.0)
	wall_pos.y = floor(wall_pos.y / GameConstants.WALL_SIZE_SIDE) * GameConstants.WALL_SIZE_SIDE + (GameConstants.WALL_SIZE_SIDE / 2.0)
	
	# Check if space is clear
	for wall in _walls:
		if wall.global_position.distance_to(wall_pos) < (GameConstants.WALL_SIZE_SIDE/2):
			return  # Too close to existing wall
	
	var wall = Wall.new()
	wall.net_id = Replication.generate_id()
	wall.authority = 1
	wall.global_position = wall_pos
	wall.builder_id = player.net_id
	wall.destroyed.connect(func(_id): _despawn_wall(wall))
	_world.add_child(wall)
	_walls.append(wall)
	
	# Save to database
	_save_or_update_structure(wall)
	
	# Tell clients (RELIABLE for walls)
	for peer_id in Net.get_peers():
		Net.spawn_entity.rpc_id(peer_id, {
			"type": "wall",
			"net_id": wall.net_id,
			"pos": wall_pos,
			"extra": {"builder": player.net_id}
		})


func _despawn_wall(wall: Wall) -> void:
	# Delete from database
	var structure_id = wall.get_meta("structure_id", -1)
	if structure_id >= 0:
		Persistence.delete_structure(structure_id)
	
	Net.despawn_entity.rpc(wall.net_id)
	wall.queue_free()
	_walls.erase(wall)


func _on_peer_connected(peer_id: int) -> void:
	Log.network("Peer connected: %d, loading data..." % peer_id)
	
	# Load player data from database
	var data = Persistence.load_player(peer_id)
	
	var player = Player.new()
	player.net_id = peer_id
	player.authority = 1  # Server authoritative
	
	if data.is_empty():
		# NEW PLAYER - Default spawn
		var spawn_pos = Vector2(
			randf_range(GameConstants.SPAWN_MIN.x, GameConstants.SPAWN_MAX.x),
			randf_range(GameConstants.SPAWN_MIN.y, GameConstants.SPAWN_MAX.y)
		)
		player.global_position = spawn_pos
		player.health = GameConstants.PLAYER_MAX_HEALTH
		Log.network("New player %d created at %s" % [peer_id, spawn_pos])
	else:
		# RETURNING PLAYER - Restore state
		player.global_position = Vector2(data.position_x, data.position_y)
		player.health = data.get("health", GameConstants.PLAYER_MAX_HEALTH)
		# TODO: Load level, xp, reputation, currency when systems exist
		Log.network("Loaded player %d: pos=%s, hp=%.1f" % [
			peer_id, player.global_position, player.health
		])
	
	_world.add_child(player)
	_players[peer_id] = player
	_last_input[peer_id] = {}
	_last_seq[peer_id] = 0
	
	# TODO: Load inventory when system exists
	# var inv_slots = Persistence.load_inventory(peer_id)
	# player.inventory.load_from_array(inv_slots)
	
	# Initial save (creates DB entry if new)
	_save_player(player)
	
	# Send new peer all existing entities
	for id in _players:
		var p = _players[id]
		Net.client_spawn_player.rpc_id(peer_id, {
			"peer_id": id,
			"state": p.get_replicated_state()
		})
	
	for enemy in _enemies:
		if is_instance_valid(enemy):
			var etype = "normal"
			if enemy is EnemyScout:
				etype = "scout"
			elif enemy is EnemyTank:
				etype = "tank"
			elif enemy is EnemySniper:
				etype = "sniper"
			elif enemy is EnemySwarm:
				etype = "swarm"
			
			Net.spawn_entity.rpc_id(peer_id, {
				"type": "enemy",
				"net_id": enemy.net_id,
				"pos": enemy.global_position,
				"extra": {"enemy_type": etype}
			})
	
	for wall in _walls:
		if is_instance_valid(wall):
			Net.spawn_entity.rpc_id(peer_id, {
				"type": "wall",
				"net_id": wall.net_id,
				"pos": wall.global_position,
				"extra": {"builder": wall.builder_id}
			})
	
	# Tell other peers about new player
	for other_id in Net.get_peers():
		if other_id != peer_id:
			Net.client_spawn_player.rpc_id(other_id, {
				"peer_id": peer_id,
				"state": player.get_replicated_state()
			})


func _on_peer_disconnected(peer_id: int) -> void:
	Log.network("Peer disconnected: %d, saving data..." % peer_id)
	
	if _players.has(peer_id):
		var player = _players[peer_id]
		
		# SAVE ON DISCONNECT
		_save_player(player)
		# TODO: Save inventory when system exists
		# Persistence.save_inventory(player.net_id, player.inventory.get_slots())
		
		Log.network("Saved player %d on disconnect" % peer_id)
		
		player.queue_free()
		_players.erase(peer_id)
	
	_last_input.erase(peer_id)
	_last_seq.erase(peer_id)
	
	Net.client_despawn_player.rpc(peer_id)


func _on_input_received(peer_id: int, cmd: Dictionary) -> void:
	if not cmd.has("seq") or not cmd.has("mv"):
		return
	
	var seq = cmd.get("seq", 0)
	var last = _last_seq.get(peer_id, 0)
	
	if seq <= last:
		return
	
	_last_seq[peer_id] = seq
	_last_input[peer_id] = cmd


func _respawn_player(player: Player) -> void:
	var spawn_pos = Vector2(
		randf_range(GameConstants.SPAWN_MIN.x, GameConstants.SPAWN_MAX.x),
		randf_range(GameConstants.SPAWN_MIN.y, GameConstants.SPAWN_MAX.y)
	)
	player.respawn(spawn_pos)


func _send_static_snapshot() -> void:
	"""Send reliable snapshot of all static entities (walls) for resync."""
	if Net.get_peers().is_empty():
		return
	
	var static_states = {}
	for wall in _walls:
		if is_instance_valid(wall):
			static_states[str(wall.net_id)] = {
				"type": "wall",
				"pos": wall.global_position,
				"health": wall.health,
				"builder": wall.builder_id
			}
	
	Net.client_receive_static_snapshot.rpc(static_states)
	Log.network("Sent static snapshot with %d walls" % static_states.size())


# =============================================================================
# PERSISTENCE FUNCTIONS
# =============================================================================

func _load_all_structures() -> void:
	"""Load all persisted structures from database at server startup."""
	var structures = Persistence.load_all_structures()
	
	if structures.is_empty():
		Log.network("No structures found in database")
		return
	
	Log.network("Loading %d structures from database..." % structures.size())
	
	for data in structures:
		match data.get("type", ""):
			"wall":
				_spawn_persisted_wall(data)
			_:
				push_error("Unknown structure type: %s" % data.get("type", "unknown"))

func _spawn_persisted_wall(data: Dictionary) -> void:
	"""Spawn a wall from persisted data."""
	var wall = Wall.new()
	wall.net_id = Replication.generate_id()
	wall.authority = 1
	wall.global_position = Vector2(data.position_x, data.position_y)
	wall.health = data.get("health", 100.0)
	wall.builder_id = data.get("owner_id", -1)
	wall.set_meta("structure_id", data.get("id", -1))
	wall.destroyed.connect(func(_id): _despawn_wall(wall))
	
	_world.add_child(wall)
	_walls.append(wall)

func _save_player(player: Player) -> void:
	"""Save a player's data to database."""
	var data = {
		"peer_id": player.net_id,
		"name": "Player_%d" % player.net_id,
		"position_x": player.global_position.x,
		"position_y": player.global_position.y,
		"health": player.health,
		"level": 1,  # TODO: Add level system
		"xp": 0,
		"reputation": 0.0,
		"currency": 0,
		"last_login": Time.get_unix_time_from_system()
	}
	Persistence.save_player(data)

func _save_or_update_structure(wall: Wall) -> void:
	"""Save or update a structure in database."""
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

func _autosave_all() -> void:
	"""Autosave all players and structures."""
	Log.network("Autosave started...")
	
	# Save all players
	for peer_id in _players:
		var player = _players[peer_id]
		_save_player(player)
		# TODO: Save inventory when system exists
	
	# Save all structures
	for wall in _walls:
		_save_or_update_structure(wall)
	
	Log.network("Autosaved %d players, %d structures" % [_players.size(), _walls.size()])

func _input(event: InputEvent) -> void:
	"""Admin commands for server management."""
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

func _admin_wipe_structures() -> void:
	"""ADMIN: Wipe all structures from game and database."""
	Log.warn("ADMIN: Wiping all structures...")
	
	# Delete in-memory
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	
	# Delete from database
	Persistence.wipe_all_structures()
	
	Log.warn("ADMIN: All structures wiped")

func _admin_wipe_players() -> void:
	"""ADMIN: Wipe all player data from database (NOT online players)."""
	Log.warn("ADMIN: Wiping all player data from database...")
	
	# Delete from database only (don't kick online players)
	Persistence.wipe_all_players()
	
	Log.warn("ADMIN: All player data wiped from database")
	Log.warn("ADMIN: Online players must reconnect to reset")

func _admin_show_stats() -> void:
	"""ADMIN: Show persistence statistics."""
	var stats = Persistence.get_stats()
	Log.network("=== PERSISTENCE STATS ===")
	Log.network("Players in DB: %d" % stats.players)
	Log.network("Structures in DB: %d" % stats.structures)
	Log.network("Players online: %d" % _players.size())
	Log.network("Walls spawned: %d" % _walls.size())
	Log.network("========================")
