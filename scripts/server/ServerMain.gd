extends Node2D
class_name ServerMain

# =============================================================================
# ServerMain.gd
# =============================================================================
# LONG DESCRIPTION:
# This is the authoritative server gameplay controller.
#
# Responsibilities:
# 1) Maintain the authoritative set of entities (players) on the server.
# 2) Receive input commands from clients (via Net.input_received signal).
# 3) Simulate movement authoritatively each physics tick using the latest input.
# 4) Replicate the world to clients:
#    - Spawn/despawn events (reliable)
#    - Snapshots of all player states (unreliable, frequent)
#    - Acknowledgements of processed input sequence numbers (unreliable, frequent)
#
# What ServerMain does NOT do:
# - interpolation (client-only)
# - prediction (client-only)
# - UI
#
# In a bigger game, this is where you'd add:
# - authoritative combat resolution
# - inventory changes, crafting
# - AI/machines
# - heat/bounty logic (authoritative)
# =============================================================================

# Spawn area helper (you already adjusted this so it's on-screen).
const SPAWN_MIN_X: int = 100
const SPAWN_MAX_X: int = 220
const SPAWN_MIN_Y: int = 100
const SPAWN_MAX_Y: int = 160

# Root node that holds Player nodes.
var _players_root: Node2D

# peer_id -> Player node (authoritative entities)
var _players: Dictionary = {}

# peer_id -> latest input cmd (Dictionary). Empty dict means "no input yet".
var _last_input: Dictionary = {}

# peer_id -> last accepted input sequence number.
# This is what we send back to each client as ack_seq.
var _last_seq: Dictionary = {}

# A monotonically increasing server tick counter.
# Used for interpolation and debugging.
var _server_tick: int = 0


# -----------------------------------------------------------------------------
# _ready()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Create a Players container node.
# - Connect Net signals so we receive peer connect/disconnect and input events.
#
# WHERE CALLED:
# - Godot calls _ready() once when the node enters the scene tree.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _ready() -> void:
	randomize()

	_players_root = Node2D.new()
	_players_root.name = "Players"
	add_child(_players_root)

	var title: Label = Label.new()
	title.text = "SERVER"
	title.position = Vector2(10, 10)
	add_child(title)

	# Listen to networking events from the Net AutoLoad.
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.input_received.connect(_on_input_received)


# -----------------------------------------------------------------------------
# _physics_process(delta)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Run the authoritative simulation at the physics tick rate.
# - Build and broadcast snapshots + acks.
#
# WHERE CALLED:
# - Godot calls _physics_process() every physics frame.
#
# RETURNS:
# - Nothing.
#
# NOTE:
# - For now we snapshot every physics tick.
# - Later you might snapshot at 20Hz and simulate at 60Hz.
# -----------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if not Net.is_server():
		return

	_server_tick += 1

	# If nobody connected, there's nothing to replicate.
	# We still tick the server counter for consistent timing.
	if Net.get_peers().is_empty():
		return

	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)

	# -------------------------------------------------------------------------
	# 1) Authoritative simulation: apply latest input to each player.
	# -------------------------------------------------------------------------
	for id_var in _players.keys():
		var peer_id: int = int(id_var)
		var p: Player = _players[peer_id] as Player

		var cmd: Dictionary = (_last_input.get(peer_id, {}) as Dictionary)

		var mv: Vector2 = Vector2.ZERO
		var aim: Vector2 = Vector2.ZERO
		var btn: int = 0

		if not cmd.is_empty():
			mv = cmd.get("mv", Vector2.ZERO)
			aim = cmd.get("aim", Vector2.ZERO)
			btn = int(cmd.get("btn", 0))

		p.apply_input(mv, aim, btn, dt)

	# -------------------------------------------------------------------------
	# 2) Build snapshot: "photo" of world state (all players).
	# -------------------------------------------------------------------------
	var snap: Dictionary = {"tick": _server_tick, "states": {}}
	var states: Dictionary = snap["states"] as Dictionary

	for id_var in _players.keys():
		var peer_id: int = int(id_var)
		var pp: Player = _players[peer_id] as Player
		states[peer_id] = pp.get_state()

	# Broadcast snapshot to all clients (unreliable).
	Net.client_receive_snapshot.rpc(snap)

	# -------------------------------------------------------------------------
	# 3) Send acks: tell each client which input seq we have processed.
	# -------------------------------------------------------------------------
	for peer_id_var in Net.get_peers():
		var peer_id: int = int(peer_id_var)
		var ack: Dictionary = {
			"tick": _server_tick,
			"ack_seq": int(_last_seq.get(peer_id, 0))
		}
		Net.client_receive_ack.rpc_id(peer_id, ack)


# -----------------------------------------------------------------------------
# _on_peer_connected(peer_id)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Server-side: create an authoritative Player for the new connection.
# - Perform late-join replication:
#   (A) New peer receives spawns for ALL existing players (full roster).
#   (B) Existing peers receive spawn for the new player.
#
# WHERE CALLED:
# - Net emits peer_connected(peer_id) when ENet accepts a new connection.
#
# RETURNS:
# - Nothing.
#
# WHY:
# - Ensures every client ends up with the same set of player entities.
# -----------------------------------------------------------------------------
func _on_peer_connected(peer_id: int) -> void:
	print("Server: peer connected: ", peer_id)

	# Create authoritative player entity for this peer.
	var p: Player = Player.new()
	p.net_id = peer_id
	p.is_local = false
	p.global_position = Vector2(randi_range(SPAWN_MIN_X, SPAWN_MAX_X), randi_range(SPAWN_MIN_Y, SPAWN_MAX_Y))
	_players_root.add_child(p)

	_players[peer_id] = p
	_last_input[peer_id] = {} # empty dict => no input yet
	_last_seq[peer_id] = 0

	# (A) Send the new peer ALL existing players (including itself).
	for id_var in _players.keys():
		var id: int = int(id_var)
		var existing: Player = _players[id] as Player
		var payload_to_new: Dictionary = {"peer_id": id, "state": existing.get_state()}
		Net.client_spawn_player.rpc_id(peer_id, payload_to_new)

	# (B) Send everyone else the NEW player.
	var payload_new: Dictionary = {"peer_id": peer_id, "state": p.get_state()}
	for other_id_var in Net.get_peers():
		var other_id: int = int(other_id_var)
		if other_id != peer_id:
			Net.client_spawn_player.rpc_id(other_id, payload_new)


# -----------------------------------------------------------------------------
# _on_peer_disconnected(peer_id)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Server-side cleanup when a peer disconnects.
# - Remove authoritative entity and broadcast despawn to clients.
#
# WHERE CALLED:
# - Net emits peer_disconnected(peer_id) when a connection is lost/closed.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _on_peer_disconnected(peer_id: int) -> void:
	print("Server: peer disconnected: ", peer_id)

	if _players.has(peer_id):
		var p: Player = _players[peer_id] as Player
		p.queue_free()
		_players.erase(peer_id)

	_last_input.erase(peer_id)
	_last_seq.erase(peer_id)

	Net.client_despawn_player.rpc(peer_id)


# -----------------------------------------------------------------------------
# _on_input_received(peer_id, cmd)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Receive input command from a client, validate it, and store it.
#
# WHERE CALLED:
# - Net emits input_received(peer_id, cmd) when server_receive_input RPC is called.
#
# RETURNS:
# - Nothing.
#
# VALIDATION:
# - Requires cmd has "seq" and "mv".
# - Enforces monotonically increasing seq per peer.
#
# WHY:
# - seq protects against reordering/duplication and supports client reconciliation.
# -----------------------------------------------------------------------------
func _on_input_received(peer_id: int, cmd: Dictionary) -> void:
	if not cmd.has("seq") or not cmd.has("mv"):
		return

	var seq: int = int(cmd.get("seq", 0))
	var last: int = int(_last_seq.get(peer_id, 0))
	if seq <= last:
		return

	_last_seq[peer_id] = seq
	_last_input[peer_id] = cmd


# -----------------------------------------------------------------------------
# randi_range(a, b)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Helper for inclusive random integer range.
#
# WHERE CALLED:
# - _on_peer_connected for spawn positions.
#
# RETURNS:
# - int in [a, b]
# -----------------------------------------------------------------------------
func randi_range(a: int, b: int) -> int:
	return a + int(randi() % (b - a + 1))
