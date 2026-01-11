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
signal static_snapshot_received(states: Dictionary)

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
	
	var peer: MultiplayerPeer
	if GameConstants.USE_WEBSOCKET:
		peer = WebSocketMultiplayerPeer.new()
		var err = peer.create_server(port)
		if err != OK:
			push_error("Net.start_server (WebSocket) failed: %s" % err)
			return
		print("Net: WebSocket server listening on port ", port)
	else:
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_server(port, max_clients)
		if err != OK:
			push_error("Net.start_server (ENet) failed: %s" % err)
			return
		print("Net: ENet server listening on port ", port)
	
	_sm.multiplayer_peer = peer
	_sm.peer_connected.connect(func(id): peer_connected.emit(id))
	_sm.peer_disconnected.connect(func(id): peer_disconnected.emit(id))
	
	server_started.emit(port)


func connect_client(host: String, port: int) -> void:
	_ensure_scene_multiplayer()
	
	var peer: MultiplayerPeer
	if GameConstants.USE_WEBSOCKET:
		peer = WebSocketMultiplayerPeer.new()
		var protocol = "wss://" if port == 443 else "ws://"
		var url = protocol + host + ":" + str(port)
		var err = peer.create_client(url)
		if err != OK:
			push_error("Net.connect_client (WebSocket) failed: %s" % err)
			client_connection_failed.emit()
			return
		print("Net: WebSocket client connecting to ", url)
	else:
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_client(host, port)
		if err != OK:
			push_error("Net.connect_client (ENet) failed: %s" % err)
			client_connection_failed.emit()
			return
		print("Net: ENet client connecting to %s:%d" % [host, port])
	
	_sm.multiplayer_peer = peer
	
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


@rpc("any_peer", "reliable")
func client_receive_static_snapshot(states: Dictionary) -> void:
	if is_server():
		return
	static_snapshot_received.emit(states)


# NEW: Entity spawning/despawning
@rpc("any_peer", "reliable")
func spawn_entity(data: Dictionary) -> void:
	if is_server():
		return
	
	print("CLIENT Net: Received spawn_entity: ", data)
	
	var type = data.get("type", "")
	var net_id = data.get("net_id", 0)
	var pos = data.get("pos", Vector2.ZERO)
	var extra = data.get("extra", {})
	
	var entity: NetworkedEntity = null
	
	match type:
		"bullet":
			# SKIP bullets fired by local player (already predicted)
			var owner_id = extra.get("owner", 0)
			if owner_id == get_unique_id():
				print("CLIENT Net: Skipping own bullet (already predicted)")
				return
			
			entity = Bullet.new()
			entity.initialize(pos, extra.get("dir", Vector2.RIGHT), owner_id)
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
		print("CLIENT Net: Spawned ", type, " with net_id ", net_id, " at ", pos)
	else:
		print("CLIENT Net: ERROR - Failed to create entity type: ", type)


@rpc("any_peer", "reliable")
func despawn_entity(net_id: int) -> void:
	if is_server():
		return
	print("CLIENT Net: Despawning entity ", net_id)
	var entity = Replication.get_entity(net_id)
	if entity:
		entity.queue_free()
	else:
		print("CLIENT Net: WARNING - Entity ", net_id, " not found in Replication")
