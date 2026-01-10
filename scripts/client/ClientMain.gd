extends Node2D
class_name ClientMain

# =============================================================================
# ClientMain.gd
# =============================================================================
# Client with prediction, reconciliation, and interpolation.
# =============================================================================

var _world: Node2D
var _players: Dictionary = {}  # peer_id -> Player
var _my_id: int = 0

# Prediction
var _input_seq: int = 0
var _pending_inputs: Array = []
var _predicted_states: Dictionary = {}

# Interpolation
var _latest_tick: int = 0
var _snap_buffers: Dictionary = {}  # net_id -> Array[{tick, state}]
var _last_server_state: Dictionary = {}


func _ready() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	
	var title = Label.new()
	title.text = "CLIENT - WASD=Move, Mouse=Aim, LMB=Shoot, RMB=Build"
	title.position = Vector2(10, 10)
	add_child(title)
	
	Net.client_connected.connect(func(id): 
		_my_id = id
		print("CLIENT: My ID is ", id)
	)
	Net.spawn_received.connect(_on_spawn_player)
	Net.despawn_received.connect(_on_despawn_player)
	Net.snapshot_received.connect(_on_snapshot)
	Net.ack_received.connect(_on_ack)


func _physics_process(_delta: float) -> void:
	if _my_id == 0:
		return
	
	var dt = GameConstants.FIXED_DELTA
	
	# Local prediction
	if _players.has(_my_id):
		_send_and_predict(dt)
	
	# Interpolate ALL non-local entities (players, enemies, walls)
	_interpolate_all_entities()


func _send_and_predict(dt: float) -> void:
	var player = _players[_my_id]
	
	# Sample input
	var mv = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)
	
	var aim = (get_global_mouse_position() - player.global_position).normalized()
	
	var btn = 0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		btn |= GameConstants.BTN_SHOOT
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		btn |= GameConstants.BTN_BUILD
	
	_input_seq += 1
	var cmd = {"seq": _input_seq, "mv": mv, "aim": aim, "btn": btn}
	
	# Send to server
	Net.server_receive_input.rpc_id(1, cmd)
	
	# Predict locally
	player.apply_input(mv, aim, btn, dt)
	
	# Store for reconciliation
	_pending_inputs.append(cmd)
	_predicted_states[_input_seq] = player.get_replicated_state()
	
	if _pending_inputs.size() > 256:
		_pending_inputs.pop_front()


func _interpolate_all_entities() -> void:
	"""Interpolate all non-local entities (remote players, enemies, walls)."""
	var render_tick = _latest_tick - GameConstants.INTERP_DELAY_TICKS
	if render_tick <= 0:
		return
	
	# Interpolate all entities with snapshot buffers
	for net_id in _snap_buffers:
		var entity = Replication.get_entity(net_id)
		if not entity or not is_instance_valid(entity):
			continue
		
		# Skip local player (we predict it)
		if entity is Player and entity.net_id == _my_id:
			continue
		
		_interpolate_entity(entity, render_tick)


func _interpolate_entity(entity: NetworkedEntity, render_tick: int) -> void:
	"""Interpolate a single entity between snapshots."""
	var buf = _snap_buffers.get(entity.net_id, [])
	if buf.size() < 2:
		return
	
	# Find surrounding snapshots
	var i = 0
	while i < buf.size() - 1 and buf[i + 1]["tick"] < render_tick:
		i += 1
	
	var a = buf[i]
	var b = buf[min(i + 1, buf.size() - 1)]
	
	var ta = float(a["tick"])
	var tb = float(b["tick"])
	if tb <= ta:
		return
	
	var t = clamp((render_tick - ta) / (tb - ta), 0.0, 1.0)
	
	var sa = a["state"]
	var sb = b["state"]
	
	# Interpolate position and rotation
	if sa.has("p") and sb.has("p"):
		entity.global_position = sa["p"].lerp(sb["p"], t)
	if sa.has("r") and sb.has("r"):
		entity.rotation = lerp_angle(sa["r"], sb["r"], t)


func _on_spawn_player(payload: Dictionary) -> void:
	var peer_id = payload["peer_id"]
	
	print("CLIENT: Received spawn for player ", peer_id)
	
	if _my_id == 0:
		_my_id = Net.get_unique_id()
	
	if _players.has(peer_id):
		_players[peer_id].apply_replicated_state(payload["state"])
		return
	
	var player = Player.new()
	player.net_id = peer_id
	player.is_local = (peer_id == _my_id)
	
	# Client predicts own player
	if player.is_local:
		player.authority = _my_id
	else:
		player.authority = 1
	
	_world.add_child(player)
	_players[peer_id] = player
	player.apply_replicated_state(payload["state"])
	
	print("CLIENT: Spawned player ", peer_id, " at ", player.global_position)
	
	if not _snap_buffers.has(peer_id):
		_snap_buffers[peer_id] = []


func _on_despawn_player(peer_id: int) -> void:
	print("CLIENT: Despawning player ", peer_id)
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)
	_snap_buffers.erase(peer_id)


func _on_snapshot(snap: Dictionary) -> void:
	_latest_tick = snap.get("tick", _latest_tick)
	var states = snap.get("states", {})
	
	# DEBUG: Print snapshot contents occasionally
	if _latest_tick % 120 == 0:
		print("CLIENT: Snapshot tick ", _latest_tick, " contains entities: ", states.keys())
		print("CLIENT: Registered entities: ", Replication._entities.keys())
	
	# Process all entities in snapshot (players, enemies, walls, bullets)
	for net_id_str in states:
		var net_id = int(net_id_str)
		var state = states[net_id_str]
		
		# Special handling for local player (store for reconciliation)
		if net_id == _my_id:
			_last_server_state = state
			continue
		
		# All other entities: add to interpolation buffer
		if not _snap_buffers.has(net_id):
			_snap_buffers[net_id] = []
		
		var buf = _snap_buffers[net_id]
		buf.append({"tick": _latest_tick, "state": state})
		
		# Keep buffer bounded
		while buf.size() > 40:
			buf.pop_front()


func _on_ack(ack: Dictionary) -> void:
	var ack_seq = ack.get("ack_seq", 0)
	if ack_seq <= 0 or _last_server_state.is_empty() or not _players.has(_my_id):
		return
	
	if not _predicted_states.has(ack_seq):
		_drop_confirmed(ack_seq)
		return
	
	var player = _players[_my_id]
	var predicted = _predicted_states[ack_seq]
	var pred_pos = predicted.get("p", Vector2.ZERO)
	var srv_pos = _last_server_state.get("p", Vector2.ZERO)
	
	if pred_pos.distance_to(srv_pos) < GameConstants.RECONCILE_POSITION_THRESHOLD:
		_drop_confirmed(ack_seq)
		return
	
	# Reconcile: rewind and replay
	player.apply_replicated_state(_last_server_state)
	
	var replay = []
	for cmd in _pending_inputs:
		if cmd["seq"] > ack_seq:
			replay.append(cmd)
	
	_pending_inputs = replay
	_predicted_states.clear()
	
	for cmd in _pending_inputs:
		player.apply_input(cmd["mv"], cmd["aim"], cmd["btn"], GameConstants.FIXED_DELTA)
		_predicted_states[cmd["seq"]] = player.get_replicated_state()


func _drop_confirmed(ack_seq: int) -> void:
	var replay = []
	for cmd in _pending_inputs:
		if cmd["seq"] > ack_seq:
			replay.append(cmd)
	_pending_inputs = replay
	
	for seq in _predicted_states.keys():
		if int(seq) <= ack_seq:
			_predicted_states.erase(seq)
