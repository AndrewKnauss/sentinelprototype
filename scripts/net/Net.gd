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
signal username_received(peer_id: int, username: String)  # Server receives username from client
signal username_accepted(success: bool, message: String)  # Client receives validation result

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
			Log.error("WebSocket server failed: %s" % err)
			return
		Log.network("WebSocket server listening on port %d" % port)
	else:
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_server(port, max_clients)
		if err != OK:
			Log.error("ENet server failed: %s" % err)
			return
		Log.network("ENet server listening on port %d" % port)
	
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
			Log.error("WebSocket client failed: %s" % err)
			client_connection_failed.emit()
			return
		Log.network("WebSocket client connecting to %s" % url)
	else:
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_client(host, port)
		if err != OK:
			Log.error("ENet client failed: %s" % err)
			client_connection_failed.emit()
			return
		Log.network("ENet client connecting to %s:%d" % [host, port])
	
	_sm.multiplayer_peer = peer
	
	_sm.connected_to_server.connect(func():
		Log.network("Connected. My peer id: %d" % _sm.get_unique_id())
		client_connected.emit(_sm.get_unique_id())
	)
	_sm.connection_failed.connect(func():
		Log.warn("Connection failed")
		client_connection_failed.emit()
	)
	_sm.server_disconnected.connect(func():
		Log.network("Server disconnected")
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
	
	#Log.entity("Received spawn_entity: %s" % data)
	
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
				Log.entity("Skipping own bullet (already predicted)")
				return
			
			entity = Bullet.new()
			entity.initialize(pos, extra.get("dir", Vector2.RIGHT), owner_id)
		"enemy":
			var enemy_type = extra.get("enemy_type", "normal")
			match enemy_type:
				"scout":
					entity = EnemyScout.new()
				"tank":
					entity = EnemyTank.new()
				"sniper":
					entity = EnemySniper.new()
				"swarm":
					entity = EnemySwarm.new()
				_:
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
		#Log.entity("Spawned %s with net_id %d at %v" % [type, net_id, pos])
	else:
		Log.error("Failed to create entity type: %s" % type)


@rpc("any_peer", "reliable")
func despawn_entity(net_id: int) -> void:
	if is_server():
		return
	var entity = Replication.get_entity(net_id)
	if entity:
		Log.entity("Despawning entity %d" % net_id)
		entity.queue_free()
	# Silently ignore if not found - likely short-lived entity (bullet)


# ========== USERNAME SYSTEM ==========
@rpc("any_peer", "reliable")
func server_receive_username(username: String) -> void:
	"""Client sends username to server for validation."""
	if not is_server():
		return
	
	var peer_id = _sm.get_remote_sender_id()
	username_received.emit(peer_id, username)

@rpc("any_peer", "reliable")
func client_receive_username_result(success: bool, message: String) -> void:
	"""Server sends validation result back to client."""
	if is_server():
		return
	
	username_accepted.emit(success, message)
