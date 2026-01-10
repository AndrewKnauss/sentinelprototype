extends Node
#class_name Net

# =============================================================================
# Net.gd (AUTOLOAD SINGLETON)
# =============================================================================
# LONG DESCRIPTION:
# This script is the "transport + RPC wiring" layer for the whole project.
#
# It has TWO jobs:
#
# (1) Own and configure Godot’s multiplayer objects:
#     - Create a SceneMultiplayer instance.
#     - Attach an ENetMultiplayerPeer (server or client) to it.
#     - Install SceneMultiplayer into the SceneTree so RPC calls become "active".
#
# (2) Provide a stable, always-present location for RPC endpoints:
#     - In Godot, RPC calls require the target function to exist at the SAME
#       node path on all peers.
#     - When this script is AutoLoaded as "Net", it always exists at:
#         /root/Net
#       on both server and clients.
#
# IMPORTANT ARCHITECTURAL RULE:
# Net.gd should contain:
#   - connection logic
#   - RPC endpoints (send/receive)
#   - "signals" that forward received network messages to gameplay code
#
# Net.gd should NOT contain:
#   - movement rules
#   - combat / loot / bounty systems
#   - interpolation or prediction code
# That logic lives in ServerMain.gd and ClientMain.gd (and later modular classes).
# =============================================================================


# -----------------------------------------------------------------------------
# Signals (events)
# -----------------------------------------------------------------------------
# These signals are how ServerMain/ClientMain learn about network events without
# directly embedding network logic everywhere.

# Transport lifecycle
signal server_started(port: int)
signal client_connected(my_id: int)
signal client_connection_failed()
signal client_disconnected()

# Peer lifecycle (server-side events)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

# Data events:
# - input_received: emitted on the server when a client sends input
# - spawn_received, despawn_received, snapshot_received, ack_received:
#   emitted on clients when the server sends replication messages
signal input_received(peer_id: int, cmd: Dictionary)
signal spawn_received(payload: Dictionary)
signal despawn_received(peer_id: int)
signal snapshot_received(snap: Dictionary)
signal ack_received(ack: Dictionary)


# -----------------------------------------------------------------------------
# Internal: the SceneMultiplayer instance attached to the SceneTree.
# -----------------------------------------------------------------------------
# NOTE: This is the fix for "The multiplayer instance isn't currently active".
# If SceneMultiplayer isn't installed in the SceneTree, calling .rpc() can fail.
var _sm: SceneMultiplayer = null


# -----------------------------------------------------------------------------
# _ensure_scene_multiplayer()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Creates a SceneMultiplayer instance if one does not exist yet.
# - Installs it into the SceneTree: get_tree().set_multiplayer(_sm)
#
# WHERE CALLED:
# - start_server()
# - connect_client()
#
# RETURNS:
# - Nothing. It only ensures global multiplayer is configured.
#
# WHY:
# - Guarantees RPC is "active" both in headless server and normal clients.
# -----------------------------------------------------------------------------
func _ensure_scene_multiplayer() -> void:
	if _sm != null:
		return

	_sm = SceneMultiplayer.new()
	get_tree().set_multiplayer(_sm)


# -----------------------------------------------------------------------------
# is_server()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Convenience helper that reports whether THIS process is running as the server.
#
# WHERE CALLED:
# - RPC endpoints (to ignore messages on the wrong side)
# - ServerMain/ClientMain for sanity checks
#
# RETURNS:
# - bool: true if SceneMultiplayer exists and is acting as server.
# -----------------------------------------------------------------------------
func is_server() -> bool:
	return _sm != null and _sm.is_server()


# -----------------------------------------------------------------------------
# get_unique_id()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Returns this peer's unique multiplayer ID.
#
# WHERE CALLED:
# - ClientMain uses it to identify "my player".
#
# RETURNS:
# - int: peer ID, or 0 if not connected / not initialized.
# -----------------------------------------------------------------------------
func get_unique_id() -> int:
	if _sm == null:
		return 0
	return _sm.get_unique_id()


# -----------------------------------------------------------------------------
# get_peers()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Returns the list of connected peer IDs (server-side mostly).
#
# WHERE CALLED:
# - ServerMain when broadcasting spawns / snapshots / acks
#
# RETURNS:
# - PackedInt32Array: list of peers, or empty if not initialized.
# -----------------------------------------------------------------------------
func get_peers() -> PackedInt32Array:
	if _sm == null:
		return PackedInt32Array()
	return _sm.get_peers()


# -----------------------------------------------------------------------------
# start_server(port, max_clients)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Start an ENet server listening on the specified port.
# - Hook peer_connected / peer_disconnected signals.
#
# WHERE CALLED:
# - Bootstrap.gd when launched with "--server"
#
# RETURNS:
# - Nothing. Emits server_started(port) on success.
#
# WHY:
# - Separates low-level ENet setup from gameplay server code.
# -----------------------------------------------------------------------------
func start_server(port: int, max_clients: int = 64) -> void:
	_ensure_scene_multiplayer()

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, max_clients)
	if err != OK:
		push_error("Net.start_server: create_server failed: %s" % err)
		return

	# Attach the peer to the SceneMultiplayer to activate networking.
	_sm.multiplayer_peer = peer

	# Forward peer connect/disconnect events.
	_sm.peer_connected.connect(func(id: int) -> void:
		peer_connected.emit(id)
	)
	_sm.peer_disconnected.connect(func(id: int) -> void:
		peer_disconnected.emit(id)
	)

	print("Net: Server listening on port ", port)
	server_started.emit(port)


# -----------------------------------------------------------------------------
# connect_client(host, port)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Connect to an ENet server at host:port.
# - Hook connected_to_server / connection_failed / server_disconnected signals.
#
# WHERE CALLED:
# - Bootstrap.gd in client mode (default)
#
# RETURNS:
# - Nothing. Emits client_connected(my_id) on success.
# -----------------------------------------------------------------------------
func connect_client(host: String, port: int) -> void:
	_ensure_scene_multiplayer()

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(host, port)
	if err != OK:
		push_error("Net.connect_client: create_client failed: %s" % err)
		client_connection_failed.emit()
		return

	_sm.multiplayer_peer = peer

	print("Net: Client connecting to %s:%d" % [host, port])

	_sm.connected_to_server.connect(func() -> void:
		var my_id: int = _sm.get_unique_id()
		print("Net: Connected. My peer id: ", my_id)
		client_connected.emit(my_id)
	)
	_sm.connection_failed.connect(func() -> void:
		print("Net: Connection failed.")
		client_connection_failed.emit()
	)
	_sm.server_disconnected.connect(func() -> void:
		print("Net: Server disconnected.")
		client_disconnected.emit()
	)


# =============================================================================
# RPC ENDPOINTS
# =============================================================================
# IMPORTANT:
# These functions are called over the network via .rpc() / .rpc_id().
# They MUST exist on both server and clients at the SAME node path.
# Because this is an AutoLoad named "Net", the path is always /root/Net.
# =============================================================================


# -----------------------------------------------------------------------------
# server_receive_input(cmd)    (CLIENT -> SERVER)
# -----------------------------------------------------------------------------
# PURPOSE:
# - This is called by clients to send "inputs" to the authoritative server.
#
# WHERE CALLED:
# - ClientMain.gd calls:
#     Net.server_receive_input.rpc_id(1, cmd)
#   (Server is always peer ID 1 in Godot’s high-level networking.)
#
# RETURNS:
# - Nothing. On server, emits input_received(peer_id, cmd) so ServerMain can
#   apply validation and store it.
#
# NETWORK RELIABILITY:
# - Marked "unreliable" for typical shooter-style input streams.
#   For localhost testing you can temporarily change to "reliable".
# -----------------------------------------------------------------------------
@rpc("any_peer", "unreliable")
func server_receive_input(cmd: Dictionary) -> void:
	if not is_server():
		return

	# Which client sent this RPC?
	var peer_id: int = _sm.get_remote_sender_id()

	# Forward to server gameplay code.
	input_received.emit(peer_id, cmd)


# -----------------------------------------------------------------------------
# client_spawn_player(payload)  (SERVER -> CLIENTS)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Server tells clients: "A player entity with peer_id X exists, with this state."
#
# WHERE CALLED:
# - ServerMain.gd calls Net.client_spawn_player.rpc_id(...)
#
# RETURNS:
# - Nothing. On clients, emits spawn_received(payload).
#
# WHY:
# - Keep spawn logic out of Net; ClientMain decides what to instantiate.
# -----------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func client_spawn_player(payload: Dictionary) -> void:
	if is_server():
		return
	spawn_received.emit(payload)


# -----------------------------------------------------------------------------
# client_despawn_player(peer_id) (SERVER -> CLIENTS)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Server tells clients: "That player entity is gone, remove it."
#
# WHERE CALLED:
# - ServerMain.gd calls Net.client_despawn_player.rpc(...)
#
# RETURNS:
# - Nothing. On clients, emits despawn_received(peer_id).
# -----------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func client_despawn_player(peer_id: int) -> void:
	if is_server():
		return
	despawn_received.emit(peer_id)


# -----------------------------------------------------------------------------
# client_receive_snapshot(snap) (SERVER -> CLIENTS)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Server tells clients the latest authoritative world snapshot.
# - Clients use this for:
#   - remote interpolation buffers
#   - local reconciliation reference state
#
# WHERE CALLED:
# - ServerMain.gd every physics tick (or at a set snapshot rate)
#
# RETURNS:
# - Nothing. On clients, emits snapshot_received(snap).
#
# RELIABILITY:
# - Unreliable: missing a snapshot is okay; the next one will arrive soon.
# -----------------------------------------------------------------------------
@rpc("any_peer", "unreliable")
func client_receive_snapshot(snap: Dictionary) -> void:
	if is_server():
		return
	snapshot_received.emit(snap)


# -----------------------------------------------------------------------------
# client_receive_ack(ack) (SERVER -> CLIENTS)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Server tells each client: "I have processed inputs up through ack_seq."
# - Clients use this to reconcile prediction:
#   - drop confirmed inputs
#   - rewind/replay if error is large
#
# WHERE CALLED:
# - ServerMain.gd sends this per-client, typically every tick.
#
# RETURNS:
# - Nothing. On clients, emits ack_received(ack).
#
# RELIABILITY:
# - Unreliable is usually fine; you’ll get another ack soon.
# -----------------------------------------------------------------------------
@rpc("any_peer", "unreliable")
func client_receive_ack(ack: Dictionary) -> void:
	if is_server():
		return
	ack_received.emit(ack)
