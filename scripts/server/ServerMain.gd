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

const ENEMY_SPAWN_POSITIONS = [
	Vector2(200, 200),
	Vector2(600, 200),
	Vector2(400, 400)
]
const STATIC_SNAPSHOT_INTERVAL: float = 5.0


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
				_spawn_bullet(player.global_position, aim, peer_id)
			
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


func _cleanup_bullets() -> void:
	"""Remove bullets that have been freed (collision detection happens in Bullet.gd)."""
	var bullets_to_remove = []
	
	for bullet in _bullets:
		if not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			bullets_to_remove.append(bullet)
	
	# Clean up list
	for bullet in bullets_to_remove:
		_bullets.erase(bullet)


func _spawn_bullet(pos: Vector2, dir: Vector2, owner: int) -> void:
	var bullet = Bullet.new()
	bullet.net_id = Replication.generate_id()
	bullet.authority = 1
	bullet.initialize(pos, dir.normalized(), owner)
	_world.add_child(bullet)
	_bullets.append(bullet)
	
	# Tell clients
	Net.spawn_entity.rpc({
		"type": "bullet",
		"net_id": bullet.net_id,
		"pos": pos,
		"extra": {"dir": dir.normalized(), "owner": owner}
	})


func _spawn_enemy(pos: Vector2) -> void:
	var enemy = Enemy.new()
	enemy.net_id = Replication.generate_id()
	enemy.authority = 1
	enemy.global_position = pos
	enemy.died.connect(func(_id): _respawn_enemy(enemy))
	enemy.wants_to_shoot.connect(func(dir): _spawn_bullet(enemy.global_position, dir, 0))
	_world.add_child(enemy)
	_enemies.append(enemy)
	
	# Tell clients
	Net.spawn_entity.rpc({
		"type": "enemy",
		"net_id": enemy.net_id,
		"pos": pos,
		"extra": {}
	})


func _respawn_enemy(enemy: Enemy) -> void:
	# Despawn
	Net.despawn_entity.rpc(enemy.net_id)
	enemy.queue_free()
	_enemies.erase(enemy)
	
	# Respawn after delay
	await get_tree().create_timer(GameConstants.ENEMY_RESPAWN_TIME).timeout
	var spawn_pos = ENEMY_SPAWN_POSITIONS[randi() % ENEMY_SPAWN_POSITIONS.size()]
	_spawn_enemy(spawn_pos)


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
	
	# Tell clients (RELIABLE for walls)
	for peer_id in Net.get_peers():
		Net.spawn_entity.rpc_id(peer_id, {
			"type": "wall",
			"net_id": wall.net_id,
			"pos": wall_pos,
			"extra": {"builder": player.net_id}
		})


func _despawn_wall(wall: Wall) -> void:
	Net.despawn_entity.rpc(wall.net_id)
	wall.queue_free()
	_walls.erase(wall)


func _on_peer_connected(peer_id: int) -> void:
	print("Server: peer connected: ", peer_id)
	
	var spawn_pos = Vector2(
		randf_range(GameConstants.SPAWN_MIN.x, GameConstants.SPAWN_MAX.x),
		randf_range(GameConstants.SPAWN_MIN.y, GameConstants.SPAWN_MAX.y)
	)
	
	var player = Player.new()
	player.net_id = peer_id
	player.authority = 1  # Server authoritative
	player.global_position = spawn_pos
	_world.add_child(player)
	_players[peer_id] = player
	_last_input[peer_id] = {}
	_last_seq[peer_id] = 0
	
	# Send new peer all existing entities
	for id in _players:
		var p = _players[id]
		Net.client_spawn_player.rpc_id(peer_id, {
			"peer_id": id,
			"state": p.get_replicated_state()
		})
	
	for enemy in _enemies:
		if is_instance_valid(enemy):
			Net.spawn_entity.rpc_id(peer_id, {
				"type": "enemy",
				"net_id": enemy.net_id,
				"pos": enemy.global_position,
				"extra": {}
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
	print("Server: peer disconnected: ", peer_id)
	
	if _players.has(peer_id):
		_players[peer_id].queue_free()
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
	print("SERVER: Sent static snapshot with ", static_states.size(), " walls")
