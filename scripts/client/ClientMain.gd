extends Node2D
class_name ClientMain

# =============================================================================
# ClientMain.gd
# =============================================================================
# LONG DESCRIPTION:
# This is the client gameplay controller responsible for:
#
# 1) Creating local and remote Player entities when the server tells us to spawn.
# 2) Sending local input commands to the server each tick.
# 3) Client-side prediction:
#    - Apply local input immediately so movement feels instant.
#    - Store input history and predicted states for later correction.
# 4) Interpolation for remote players:
#    - Buffer snapshots from the server.
#    - Render other players slightly "in the past" and lerp between states.
# 5) Reconciliation:
#    - When server acknowledges which inputs it processed (ack_seq),
#      compare predicted state vs server authoritative state.
#    - If divergence is large: rewind to server state and replay pending inputs.
#
# This file is where you will later extract modules/classes like:
# - PredictionController
# - InterpolationBuffer
# - NetworkedEntityManager
# =============================================================================

# Interpolation delay measured in server ticks.
# Higher values = smoother remotes but more visible delay.
const INTERP_DELAY_TICKS: int = 6

# Error threshold before we decide to rewind/replay.
const RECONCILE_POS_EPS: float = 2.5

# Root for Player nodes
var _players_root: Node2D

# peer_id -> Player
var _players: Dictionary = {}

# My peer id (assigned after connecting)
var _my_id: int = 0

# Local input sequence counter (monotonically increasing)
var _input_seq: int = 0

# -------------------------------------------------------------------------
# Prediction buffers:
# -------------------------------------------------------------------------
# pending inputs = inputs we sent but server hasn't confirmed (ack'd) yet
var _pending_inputs: Array = []  # Array[Dictionary]

# predicted state after applying a specific seq (for error measurement)
# seq -> state dict
var _predicted_state_by_seq: Dictionary = {}

# -------------------------------------------------------------------------
# Interpolation buffers:
# -------------------------------------------------------------------------
# Latest server tick we've heard about (from snapshots)
var _latest_server_tick: int = 0

# peer_id -> Array of {"tick": int, "state": Dictionary}
var _snap_buffer: Dictionary = {}

# -------------------------------------------------------------------------
# Reconciliation reference:
# -------------------------------------------------------------------------
# The server's authoritative state for *my* player from the most recent snapshot.
# Used to correct prediction.
var _last_server_state_for_me: Dictionary = {}


# -----------------------------------------------------------------------------
# _ready()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Create Players container
# - Subscribe to Net signals for spawn/despawn/snap/ack events
#
# WHERE CALLED:
# - Godot calls _ready() once when the node enters the scene tree.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _ready() -> void:
	_players_root = Node2D.new()
	_players_root.name = "Players"
	add_child(_players_root)

	var title: Label = Label.new()
	title.text = "CLIENT"
	title.position = Vector2(10, 10)
	add_child(title)

	# When connected, Net tells us our peer id.
	Net.client_connected.connect(func(id: int) -> void:
		_my_id = id
	)

	# Subscribe to server->client events
	Net.spawn_received.connect(_on_spawn)
	Net.despawn_received.connect(_on_despawn)
	Net.snapshot_received.connect(_on_snapshot)
	Net.ack_received.connect(_on_ack)


# -----------------------------------------------------------------------------
# _physics_process(delta)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Main client tick:
#   1) If we have a local player entity, send input + predict movement instantly.
#   2) Interpolate remote players from snapshot buffers.
#
# WHERE CALLED:
# - Godot calls each physics frame.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if _my_id == 0:
		# Not connected yet.
		return

	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)

	# 1) Local prediction (only if our local player exists).
	if _players.has(_my_id):
		_send_and_predict_local(dt)

	# 2) Remote interpolation
	_interpolate_remotes()


# -----------------------------------------------------------------------------
# _send_and_predict_local(dt)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Read local input (movement + aim)
# - Create an input command with a unique seq id
# - Send it to server (input-based networking)
# - Apply it locally immediately (prediction)
# - Store it for reconciliation replay
#
# WHERE CALLED:
# - _physics_process() each tick after local player exists.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _send_and_predict_local(dt: float) -> void:
	var p: Player = _players[_my_id] as Player

	# Read movement using default ui_* actions (arrow keys by default).
	var mv: Vector2 = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)
	if mv.length() > 1.0:
		mv = mv.normalized()

	# Aim direction: mouse to player.
	var aim: Vector2 = get_global_mouse_position() - p.global_position
	if aim.length() > 0.001:
		aim = aim.normalized()
	else:
		aim = Vector2.ZERO

	# Example buttons bitmask (unused for now)
	var btn: int = 0
	if Input.is_action_pressed("ui_accept"):
		btn |= 1

	# Increment seq so each input is uniquely ordered.
	_input_seq += 1

	# Input command format:
	# - seq: monotonic per client
	# - mv: movement vector
	# - aim: aim vector
	# - btn: button bitmask
	var cmd: Dictionary = {"seq": _input_seq, "mv": mv, "aim": aim, "btn": btn}

	# Send to server. Server is peer id 1.
	Net.server_receive_input.rpc_id(1, cmd)

	# Apply locally immediately for responsiveness (prediction).
	p.apply_input(mv, aim, btn, dt)

	# Store for reconciliation.
	_pending_inputs.append(cmd)
	_predicted_state_by_seq[_input_seq] = p.get_state()

	# Prevent unbounded memory growth.
	if _pending_inputs.size() > 256:
		_pending_inputs.pop_front()


# -----------------------------------------------------------------------------
# _on_spawn(payload)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Handle server telling us that a player entity exists.
# - Create a Player node if needed and apply its initial state.
#
# WHERE CALLED:
# - Net emits spawn_received(payload) when client_spawn_player RPC arrives.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _on_spawn(payload: Dictionary) -> void:
	var peer_id: int = int(payload.get("peer_id", 0))
	var st: Dictionary = payload.get("state", {}) as Dictionary
	if peer_id == 0:
		return

	# Sometimes spawn can arrive before our client_connected signal fires.
	# This is a defensive fallback to discover our id.
	if _my_id == 0:
		var uid: int = Net.get_unique_id()
		if uid != 0:
			_my_id = uid

	# If player already exists, update state.
	if _players.has(peer_id):
		var existing: Player = _players[peer_id] as Player
		existing.set_state(st)
		return

	# Create new Player node.
	var p: Player = Player.new()
	p.net_id = peer_id
	p.is_local = (peer_id == _my_id)
	_players_root.add_child(p)
	_players[peer_id] = p
	p.set_state(st)

	# Ensure buffer exists for this peer for interpolation.
	if not _snap_buffer.has(peer_id):
		_snap_buffer[peer_id] = []


# -----------------------------------------------------------------------------
# _on_despawn(peer_id)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Remove a Player node when the server says it no longer exists.
#
# WHERE CALLED:
# - Net emits despawn_received(peer_id) when client_despawn_player RPC arrives.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _on_despawn(peer_id: int) -> void:
	if _players.has(peer_id):
		var p: Player = _players[peer_id] as Player
		p.queue_free()
		_players.erase(peer_id)

	_snap_buffer.erase(peer_id)


# -----------------------------------------------------------------------------
# _on_snapshot(snap)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Receive server authoritative snapshot.
# - For my local player:
#     store server authoritative state for reconciliation reference
# - For remote players:
#     push states into interpolation buffers
#
# WHERE CALLED:
# - Net emits snapshot_received(snap) when client_receive_snapshot RPC arrives.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _on_snapshot(snap: Dictionary) -> void:
	_latest_server_tick = int(snap.get("tick", _latest_server_tick))
	var states: Dictionary = snap.get("states", {}) as Dictionary

	for k in states.keys():
		var peer_id: int = int(k)
		var st: Dictionary = states[k] as Dictionary

		# Local player: store authoritative state for reconciliation.
		if peer_id == _my_id:
			_last_server_state_for_me = st
			continue

		# Remote player: push into interpolation buffer.
		if not _snap_buffer.has(peer_id):
			_snap_buffer[peer_id] = []

		var buf: Array = _snap_buffer[peer_id] as Array
		buf.append({"tick": _latest_server_tick, "state": st})

		# Keep buffer bounded.
		while buf.size() > 40:
			buf.pop_front()

		_snap_buffer[peer_id] = buf


# -----------------------------------------------------------------------------
# _interpolate_remotes()
# -----------------------------------------------------------------------------
# PURPOSE:
# - For each remote player, sample two snapshots surrounding render_tick.
# - Lerp position and rotation for smooth motion.
#
# WHERE CALLED:
# - _physics_process() each tick
#
# RETURNS:
# - Nothing.
#
# WHY:
# - Network snapshots arrive at irregular intervals. Interpolation smooths that.
# - We intentionally render slightly "behind" (INTERP_DELAY_TICKS) so we have
#   two known snapshots to blend between.
# -----------------------------------------------------------------------------
func _interpolate_remotes() -> void:
	var render_tick: int = _latest_server_tick - INTERP_DELAY_TICKS
	if render_tick <= 0:
		return

	for id_var in _players.keys():
		var peer_id: int = int(id_var)
		if peer_id == _my_id:
			continue

		if not _snap_buffer.has(peer_id):
			continue

		var buf: Array = _snap_buffer[peer_id] as Array
		if buf.size() < 2:
			continue

		# Find the two snapshots surrounding render_tick.
		var i: int = 0
		while i < buf.size() - 1 and int((buf[i + 1] as Dictionary).get("tick", 0)) < render_tick:
			i += 1

		var a: Dictionary = buf[i] as Dictionary
		var b: Dictionary = buf[min(i + 1, buf.size() - 1)] as Dictionary

		var ta: float = float(a.get("tick", 0))
		var tb: float = float(b.get("tick", 0))
		if tb <= ta:
			continue

		# Normalized interpolation factor between the two snapshot ticks.
		var t: float = (float(render_tick) - ta) / (tb - ta)
		t = clamp(t, 0.0, 1.0)

		var sa: Dictionary = a.get("state", {}) as Dictionary
		var sb: Dictionary = b.get("state", {}) as Dictionary

		var p: Player = _players[peer_id] as Player

		var pa: Vector2 = sa.get("p", p.global_position)
		var pb: Vector2 = sb.get("p", p.global_position)
		p.global_position = pa.lerp(pb, t)

		var ra: float = float(sa.get("r", p.rotation))
		var rb: float = float(sb.get("r", p.rotation))
		p.rotation = lerp_angle(ra, rb, t)


# -----------------------------------------------------------------------------
# _on_ack(ack)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Reconciliation hook.
# - The server tells us: "I've processed inputs through ack_seq."
# - We compare our predicted state at that seq vs the server authoritative state.
# - If error is small: drop confirmed inputs and continue.
# - If error is large: rewind to server state and replay remaining inputs.
#
# WHERE CALLED:
# - Net emits ack_received(ack) when client_receive_ack RPC arrives.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _on_ack(ack: Dictionary) -> void:
	var ack_seq: int = int(ack.get("ack_seq", 0))
	if ack_seq <= 0:
		return
	if _last_server_state_for_me.is_empty():
		return
	if not _players.has(_my_id):
		return

	# If we don't have predicted history for that seq (maybe trimmed),
	# just drop inputs we can and move on.
	if not _predicted_state_by_seq.has(ack_seq):
		_drop_confirmed_inputs(ack_seq)
		return

	var p: Player = _players[_my_id] as Player
	var predicted: Dictionary = _predicted_state_by_seq[ack_seq] as Dictionary

	# Compare predicted vs server truth.
	var pred_pos: Vector2 = predicted.get("p", p.global_position)
	var srv_pos: Vector2 = _last_server_state_for_me.get("p", p.global_position)
	var err: float = srv_pos.distance_to(pred_pos)

	# If close enough, we accept and just discard old inputs.
	if err < RECONCILE_POS_EPS:
		_drop_confirmed_inputs(ack_seq)
		return

	# Otherwise: rewind to server truth...
	p.set_state(_last_server_state_for_me)

	# ...then replay remaining inputs after ack_seq.
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


# -----------------------------------------------------------------------------
# _drop_confirmed_inputs(ack_seq)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Remove inputs from our pending list that the server has already processed.
# - Also cleans predicted_state_by_seq entries for old seqs.
#
# WHERE CALLED:
# - _on_ack() in both the "small error" and "history missing" paths.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
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
