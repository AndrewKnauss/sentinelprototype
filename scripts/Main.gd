extends Node2D

# ---------------------------------------
# Sentinel Net Prototype (Godot 4)
# One script that can run as:
#   - Dedicated server: godot4 --headless -- --server
#   - Client:           godot4 -- --client   (or just godot4)
# Defaults: client connects to 127.0.0.1:24567
# ---------------------------------------

const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 24567
const MAX_CLIENTS: int = 64

# Networking tuning
const INTERP_DELAY_TICKS: int = 2       # ~100ms at 60hz
const RECONCILE_POS_EPS: float = 2.5    # pixels before rewind/replay

# Server simulation tick counter
var _server_tick: int = 0

# Containers
var _players_root: Node2D

# Shared: peer_id -> Player
var _players: Dictionary = {}

# ------------------
# Server-side storage
# ------------------
# peer_id -> latest input cmd (Dictionary). Empty dict means "no input yet".
var _server_last_input: Dictionary = {}
# peer_id -> last processed input seq (ack)
var _server_last_ack_seq: Dictionary = {}

# ------------------
# Client-side storage
# ------------------
var _my_id: int = 0
var _input_seq: int = 0

# seq -> predicted state dictionary
var _predicted_state_by_seq: Dictionary = {}
# pending input cmds
var _pending_inputs: Array = []

# peer_id -> Array of {"tick": int, "state": Dictionary}
var _snap_buffer: Dictionary = {}
var _latest_server_tick: int = 0
var _last_server_state_for_me: Dictionary = {}

func _ready() -> void:
	print("USER ARGS: ", OS.get_cmdline_user_args())
	print("ALL ARGS: ", OS.get_cmdline_args())
	
	randomize()

	_players_root = Node2D.new()
	_players_root.name = "Players"
	add_child(_players_root)

	# Simple title label so you can see mode
	var title: Label = Label.new()
	title.name = "Title"
	title.position = Vector2(10, 10)
	add_child(title)

	var mode: String = _parse_mode()
	var host: String = _parse_arg_value("--host=", DEFAULT_HOST)
	var port: int = int(_parse_arg_value("--port=", str(DEFAULT_PORT)))

	if mode == "server":
		title.text = "SERVER (ENet) :%d" % port
		_start_server(port)
	else:
		title.text = "CLIENT (ENet) -> %s:%d" % [host, port]
		_connect_client(host, port)

func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return

	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)

	if multiplayer.is_server():
		_server_step(dt)
	else:
		_client_step(dt)

# ======================
# Launch mode + arguments
# ======================

func _parse_mode() -> String:
	# IMPORTANT: user args are the ones after `--`
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--server" in args:
		return "server"
	if "--client" in args:
		return "client"
	return "client"

func _parse_arg_value(prefix: String, default_val: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return default_val

# ======================
# Network init (ENet)
# ======================

func _start_server(port: int) -> void:
	# Ensure this scene tree has an active SceneMultiplayer instance.
	var sm := SceneMultiplayer.new()
	get_tree().set_multiplayer(sm)

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("create_server failed: %s" % err)
		return

	# Attach ENet peer to the SceneMultiplayer.
	sm.multiplayer_peer = peer

	print("Server listening on port ", port)

	sm.peer_connected.connect(_on_peer_connected)
	sm.peer_disconnected.connect(_on_peer_disconnected)
	
	
func _connect_client(host: String, port: int) -> void:
	# Ensure this scene tree has an active SceneMultiplayer instance.
	var sm := SceneMultiplayer.new()
	get_tree().set_multiplayer(sm)

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(host, port)
	if err != OK:
		push_error("create_client failed: %s" % err)
		return

	# Attach ENet peer to the SceneMultiplayer.
	sm.multiplayer_peer = peer

	print("Client connecting to %s:%d" % [host, port])

	sm.connected_to_server.connect(func() -> void:
		_my_id = sm.get_unique_id()
		print("Connected. My peer id: ", _my_id)
	)
	sm.connection_failed.connect(func() -> void:
		print("Connection failed.")
	)
	sm.server_disconnected.connect(func() -> void:
		print("Server disconnected.")
	)

# ======================
# Server logic
# ======================

func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)

	# 1) Create the server-authoritative player for the new peer
	var p: Player = Player.new()
	p.net_id = peer_id
	p.is_local = false
	p.global_position = Vector2(randi_range(100, 220), randi_range(100, 160))
	_players_root.add_child(p)
	_players[peer_id] = p

	_server_last_input[peer_id] = {}
	_server_last_ack_seq[peer_id] = 0

	# 2) Send ALL existing players (including the new one) to the new peer
	for id_var in _players.keys():
		var id: int = int(id_var)
		var existing: Player = _players[id] as Player
		var payload_to_new: Dictionary = {
			"peer_id": id,
			"state": existing.get_state()
		}
		client_spawn_player.rpc_id(peer_id, payload_to_new)

	# 3) Send the NEW player to everyone else (existing peers)
	var payload_new: Dictionary = {
		"peer_id": peer_id,
		"state": p.get_state()
	}

	for other_id_var in multiplayer.get_peers():
		var other_id: int = int(other_id_var)
		if other_id != peer_id:
			client_spawn_player.rpc_id(other_id, payload_new)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)
	if _players.has(peer_id):
		var pp: Player = _players[peer_id] as Player
		pp.queue_free()
		_players.erase(peer_id)

	_server_last_input.erase(peer_id)
	_server_last_ack_seq.erase(peer_id)

	client_despawn_player.rpc(peer_id)

func _server_step(dt: float) -> void:
	# If no peers are connected yet, don’t try to RPC snapshots.
	if multiplayer.get_peers().is_empty():
		_server_tick += 1
		return
	
	_server_tick += 1

	# Simulate each player from latest input (MVP).
	for peer_id_var in _players.keys():
		var peer_id: int = int(peer_id_var)
		var p: Player = _players[peer_id] as Player

		var cmd: Dictionary = (_server_last_input.get(peer_id, {}) as Dictionary)

		var mv: Vector2 = Vector2.ZERO
		var aim: Vector2 = Vector2.ZERO
		var btn: int = 0

		if not cmd.is_empty():
			mv = cmd.get("mv", Vector2.ZERO)
			aim = cmd.get("aim", Vector2.ZERO)
			btn = int(cmd.get("btn", 0))
			_server_last_ack_seq[peer_id] = int(cmd.get("seq", int(_server_last_ack_seq.get(peer_id, 0))))

		p.apply_input(mv, aim, btn, dt)

	# Build snapshot: includes everyone
	var snap: Dictionary = {
		"tick": _server_tick,
		"states": {}
	}
	var snap_states: Dictionary = snap["states"]
	for peer_id_var in _players.keys():
		var peer_id: int = int(peer_id_var)
		var pp: Player = _players[peer_id] as Player
		snap_states[peer_id] = pp.get_state()

	# Broadcast snapshot (UNRELIABLE)
	client_receive_snapshot.rpc(snap)

	# Send per-client ack (UNRELIABLE, owner-only)
	for peer_id_var in _players.keys():
		var peer_id: int = int(peer_id_var)
		var ack: Dictionary = {
			"tick": _server_tick,
			"ack_seq": int(_server_last_ack_seq.get(peer_id, 0))
		}
		client_receive_ack.rpc_id(peer_id, ack)

# Client -> server: input command (unreliable)
@rpc("any_peer", "unreliable")
func server_receive_input(cmd: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	# minimal validation
	if not cmd.has("seq") or not cmd.has("mv"):
		return

	var seq: int = int(cmd["seq"])
	var last_seq: int = int(_server_last_ack_seq.get(peer_id, 0))

	# ignore old/duplicate
	if seq <= last_seq:
		return

	# store latest input
	_server_last_input[peer_id] = cmd

# ======================
# Client logic
# ======================

func _client_step(dt: float) -> void:
	if _my_id == 0:
		return

	# Local predict + send
	if _players.has(_my_id):
		_client_send_and_predict_local(dt)

	# Interpolate remote players
	_client_interpolate_remotes()

func _client_send_and_predict_local(dt: float) -> void:
	var p: Player = _players[_my_id] as Player

	# Movement from default actions (ui_* exist in new projects)
	var mv: Vector2 = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)
	if mv.length() > 1.0:
		mv = mv.normalized()

	# Aim toward mouse
	var aim: Vector2 = get_global_mouse_position() - p.global_position
	if aim.length() > 0.001:
		aim = aim.normalized()
	else:
		aim = Vector2.ZERO

	# Buttons bitmask example
	var btn: int = 0
	if Input.is_action_pressed("ui_accept"):
		btn |= 1

	_input_seq += 1
	var cmd: Dictionary = {"seq": _input_seq, "mv": mv, "aim": aim, "btn": btn}

	# Server is always peer id 1
	server_receive_input.rpc_id(1, cmd)

	# Predict locally
	p.apply_input(mv, aim, btn, dt)

	# Save history for reconciliation
	_pending_inputs.append(cmd)
	_predicted_state_by_seq[_input_seq] = p.get_state()

	# Cap buffers
	if _pending_inputs.size() > 256:
		_pending_inputs.pop_front()

# Server -> clients: spawn/despawn (reliable)
@rpc("authority", "reliable")
func client_spawn_player(payload: Dictionary) -> void:
	print("client_spawn_player")
	
	if multiplayer.is_server():
		return
		
	var peer_id: int = int(payload.get("peer_id", 0))
	var st: Dictionary = payload.get("state", {}) as Dictionary

	if peer_id == 0:
		return
	if _players.has(peer_id):
		var existing: Player = _players[peer_id] as Player
		existing.set_state(st)
		return

	var p: Player = Player.new()
	p.net_id = peer_id
	p.is_local = (peer_id == multiplayer.get_unique_id())
	_players_root.add_child(p)
	_players[peer_id] = p

	p.set_state(st)

	if not _snap_buffer.has(peer_id):
		_snap_buffer[peer_id] = []

@rpc("authority", "reliable")
func client_despawn_player(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	
	if _players.has(peer_id):
		var p: Player = _players[peer_id] as Player
		p.queue_free()
		_players.erase(peer_id)
	_snap_buffer.erase(peer_id)

# Server -> clients: snapshot (unreliable)
@rpc("authority", "unreliable")
func client_receive_snapshot(snap: Dictionary) -> void:
	if multiplayer.is_server():
			return
	
	_latest_server_tick = int(snap.get("tick", _latest_server_tick))

	var states: Dictionary = snap.get("states", {}) as Dictionary
	for k in states.keys():
		var peer_id: int = int(k)
		var st: Dictionary = states[k] as Dictionary

		# My player: store authoritative server state for reconciliation
		if peer_id == multiplayer.get_unique_id():
			_last_server_state_for_me = st
			continue

		# Remotes: buffer for interpolation
		if not _snap_buffer.has(peer_id):
			_snap_buffer[peer_id] = []

		var buf: Array = _snap_buffer[peer_id] as Array
		buf.append({"tick": _latest_server_tick, "state": st})

		# Cap buffer size
		while buf.size() > 40:
			buf.pop_front()

		_snap_buffer[peer_id] = buf

func _client_interpolate_remotes() -> void:
	var render_tick: int = _latest_server_tick - INTERP_DELAY_TICKS
	if render_tick <= 0:
		return

	for peer_id_var in _players.keys():
		var peer_id: int = int(peer_id_var)
		if peer_id == _my_id:
			continue
		if not _snap_buffer.has(peer_id):
			continue

		var buf: Array = _snap_buffer[peer_id] as Array
		if buf.size() < 2:
			continue

		# Find two snapshots around render_tick
		var i: int = 0
		while i < buf.size() - 1 and int((buf[i + 1] as Dictionary).get("tick", 0)) < render_tick:
			i += 1

		var a: Dictionary = buf[i] as Dictionary
		var b: Dictionary = buf[min(i + 1, buf.size() - 1)] as Dictionary

		var ta: float = float(a.get("tick", 0))
		var tb: float = float(b.get("tick", 0))
		if tb <= ta:
			continue

		var t: float = (float(render_tick) - ta) / (tb - ta)
		t = clamp(t, 0.0, 1.0)

		var sa: Dictionary = a.get("state", {}) as Dictionary
		var sb: Dictionary = b.get("state", {}) as Dictionary

		if not _players.has(peer_id):
			continue
		var p: Player = _players[peer_id] as Player

		var pa: Vector2 = sa.get("p", p.global_position)
		var pb: Vector2 = sb.get("p", p.global_position)
		p.global_position = pa.lerp(pb, t)

		var ra: float = float(sa.get("r", p.rotation))
		var rb: float = float(sb.get("r", p.rotation))
		p.rotation = lerp_angle(ra, rb, t)

# Server -> client: ack (unreliable)
@rpc("authority", "unreliable")
func client_receive_ack(ack: Dictionary) -> void:
	if multiplayer.is_server():
		return
		
	var ack_seq: int = int(ack.get("ack_seq", 0))
	if ack_seq <= 0:
		return
	if _last_server_state_for_me.is_empty():
		return
	if not _players.has(_my_id):
		return

	# If we don't have predicted state for that seq, just drop confirmed inputs
	if not _predicted_state_by_seq.has(ack_seq):
		_drop_confirmed_inputs(ack_seq)
		return

	var p: Player = _players[_my_id] as Player

	var predicted: Dictionary = _predicted_state_by_seq[ack_seq] as Dictionary
	var pred_pos: Vector2 = predicted.get("p", p.global_position)
	var srv_pos: Vector2 = _last_server_state_for_me.get("p", p.global_position)

	var err: float = srv_pos.distance_to(pred_pos)

	if err < RECONCILE_POS_EPS:
		_drop_confirmed_inputs(ack_seq)
		return

	# Rewind to authoritative server state
	p.set_state(_last_server_state_for_me)

	# Replay inputs after ack_seq
	var replay: Array = []
	for cmd_var in _pending_inputs:
		var cmd: Dictionary = cmd_var as Dictionary
		if int(cmd.get("seq", 0)) > ack_seq:
			replay.append(cmd)

	_pending_inputs = replay
	_predicted_state_by_seq.clear()

	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	for cmd_var in _pending_inputs:
		var cmd: Dictionary = cmd_var as Dictionary
		p.apply_input(cmd["mv"], cmd["aim"], int(cmd.get("btn", 0)), dt)
		_predicted_state_by_seq[int(cmd["seq"])] = p.get_state()

func _drop_confirmed_inputs(ack_seq: int) -> void:
	var replay: Array = []
	for cmd_var in _pending_inputs:
		var cmd: Dictionary = cmd_var as Dictionary
		if int(cmd.get("seq", 0)) > ack_seq:
			replay.append(cmd)
	_pending_inputs = replay

	for k in _predicted_state_by_seq.keys():
		if int(k) <= ack_seq:
			_predicted_state_by_seq.erase(k)

# ======================
# Utility
# ======================

func randi_range(a: int, b: int) -> int:
	return a + int(randi() % (b - a + 1))
