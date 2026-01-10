extends Node
#class_name Net

# =============================================================================
# Net.gd (AUTOLOAD SINGLETON)
# =============================================================================
# Transport + RPC wiring layer for the multiplayer game.
# =============================================================================

# Signals
signal server_started(port: int)
signal client_connected(my_id: int)
signal client_connection_failed()
signal client_disconnected()
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal input_received(peer_id: int, cmd: Dictionary)
signal spawn_received(payload: Dictionary)
signal despawn_received(peer_id: int)
signal snapshot_received(snap: Dictionary)
signal ack_received(ack: Dictionary)

var _sm: SceneMultiplayer = null


func _ensure_scene_multiplayer() -> void:
	if _sm != null:
		return
	_sm = SceneMultiplayer.new()
	get_tree().set_multiplayer(_sm)


func is_server() -> bool:
	return _sm != null and _sm.is_server()


func get_unique_id() -> int:
	if _sm == null:
		return 0
	return _sm.get_unique_id()


func get_peers() -> PackedInt32Array:
	if _sm == null:
		return PackedInt32Array()
	return _sm.get_peers()


func start_server(port: int, max_clients: int = 64) -> void:
	_ensure_scene_multiplayer()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, max_clients)
	if err != OK:
		push_error("Net.start_server failed: %s" % err)
		return
	
	_sm.multiplayer_peer = peer
	_sm.peer_connected.connect(func(id): peer_connected.emit(id))
	_sm.peer_disconnected.connect(func(id): peer_disconnected.emit(id))
	
	print("Net: Server listening on port ", port)
	server_started.emit(port)


func connect_client(host: String, port: int) -> void:
	_ensure_scene_multiplayer()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(host, port)
	if err != OK:
		push_error("Net.connect_client failed: %s" % err)
		client_connection_failed.emit()
		return
	
	_sm.multiplayer_peer = peer
	print("Net: Client connecting to %s:%d" % [host, port])
	
	_sm.connected_to_server.connect(func():
		print("Net: Connected. My peer id: ", _sm.get_unique_id())
		client_connected.emit(_sm.get_unique_id())
	)
	_sm.connection_failed.connect(func():
		print("Net: Connection failed.")
		client_connection_failed.emit()
	)
	_sm.server_disconnected.connect(func():
		print("Net: Server disconnected.")
		client_disconnected.emit()
	)


# =============================================================================
# RPC ENDPOINTS
# =============================================================================

@rpc("any_peer", "unreliable")
func server_receive_input(cmd: Dictionary) -> void:
	if not is_server():
		return
	var peer_id = _sm.get_remote_sender_id()
	input_received.emit(peer_id, cmd)


@rpc("any_peer", "reliable")
func client_spawn_player(payload: Dictionary) -> void:
	if is_server():
		return
	spawn_received.emit(payload)


@rpc("any_peer", "reliable")
func client_despawn_player(peer_id: int) -> void:
	if is_server():
		return
	despawn_received.emit(peer_id)


@rpc("any_peer", "unreliable")
func client_receive_snapshot(snap: Dictionary) -> void:
	if is_server():
		return
	snapshot_received.emit(snap)


@rpc("any_peer", "unreliable")
func client_receive_ack(ack: Dictionary) -> void:
	if is_server():
		return
	ack_received.emit(ack)


# NEW: Entity spawning/despawning
@rpc("any_peer", "reliable")
func spawn_entity(data: Dictionary) -> void:
	if is_server():
		return
	
	var type = data.get("type", "")
	var net_id = data.get("net_id", 0)
	var pos = data.get("pos", Vector2.ZERO)
	var extra = data.get("extra", {})
	
	var entity: NetworkedEntity = null
	
	match type:
		"bullet":
			entity = Bullet.new()
			entity.initialize(pos, extra.get("dir", Vector2.RIGHT), extra.get("owner", 0))
		"enemy":
			entity = Enemy.new()
			entity.global_position = pos
		"wall":
			entity = Wall.new()
			entity.global_position = pos
			entity.builder_id = extra.get("builder", 0)
	
	if entity:
		entity.net_id = net_id
		entity.authority = 1
		get_tree().root.add_child(entity)


@rpc("any_peer", "reliable")
func despawn_entity(net_id: int) -> void:
	if is_server():
		return
	var entity = Replication.get_entity(net_id)
	if entity:
		entity.queue_free()
