extends Node2D
class_name ClientMain

# =============================================================================
# ClientMain.gd - Client-Side Prediction & Interpolation
# =============================================================================
# 
# ARCHITECTURE OVERVIEW:
# This client uses different strategies for different entity types:
#
# LOCAL PLAYER (you):
#   - CLIENT-SIDE PREDICTION: Apply inputs immediately for zero-latency feel
#   - Send inputs to server
#   - Server simulates and sends back authoritative state
#   - RECONCILIATION: If predicted position differs from server, rewind & replay
#   - NON-PREDICTED STATE: Health/status applied immediately from server
#
# REMOTE PLAYERS (others):
#   - INTERPOLATION: Render 2 ticks behind, smoothly lerp between snapshots
#   - No prediction (we don't have their inputs)
#
# ENEMIES & WALLS:
#   - INTERPOLATION: Same as remote players
#   - Server-authoritative AI and physics
#
# WALLS:
#   - STATIC: Position set once on spawn, only health updates
#   - No interpolation needed (they don't move)
#
# BULLETS:
#   - PURE CLIENT PREDICTION: Spawn instantly, no server reconciliation
#   - Server validates damage but client handles visuals
#
# DATA FLOW:
#   1. Sample input → Send to server → Predict locally → Store state
#   2. Server snapshot arrives → Apply health → Buffer for interpolation
#   3. Server ACK arrives → Check position → Reconcile if mismatch
#   4. Every frame → Interpolate remote entities from buffered snapshots
# =============================================================================

var _world: Node2D
var _players: Dictionary = {}  # peer_id -> Player
var _my_id: int = 0
var _camera: Camera2D

# Prediction
var _input_seq: int = 0
var _pending_inputs: Array = []
var _predicted_states: Dictionary = {}

# Interpolation
var _latest_tick: int = 0
var _snap_buffers: Dictionary = {}  # net_id -> Array[{tick, state}]
var _last_server_state: Dictionary = {}

# Network diagnostics
var _debug_visible: bool = false
var _debug_label: Label
var _ammo_label: Label  # Weapon ammo display
var _last_snapshot_time: float = 0.0
var _snapshot_count: int = 0
var _last_ack_time: float = 0.0
var _ack_count: int = 0
var _reconcile_count: int = 0
var _last_ping_send: float = 0.0
var _ping_ms: float = 0.0
var _sps_samples: Array = []
var _sps_latest_ms: float = 0.0
var _last_time_snapshot: float = 0.0
var _time_last_snap_ms: float = 0.0
var _fps_samples: Array = []
#var _ticks_since_input: int = 0  # Track ticks since last active input (DISABLED)
#var _last_aim: Vector2 = Vector2.ZERO  # Track aim changes (DISABLED)

# Initialize client, setup UI, and connect to network events.
func _ready() -> void:
	
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	
	# Create camera
	_camera = Camera2D.new()
	_camera.enabled = true
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 5.0
	_world.add_child(_camera)
	
	# UI LAYER (stays fixed to screen, ignores camera)
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "UI"
	canvas_layer.layer = 10  # Always on top
	add_child(canvas_layer)
	
	# CONNECTION UI (only show if not auto-connecting)
	var auto_connect = "--auto-connect" in OS.get_cmdline_user_args()
	var ui = Control.new()
	ui.visible = not auto_connect  # Hide if auto-connecting
	canvas_layer.add_child(ui)
	
	var host_input = LineEdit.new()
	host_input.text = "web-production-5b732.up.railway.app"
	host_input.placeholder_text = "Server URL"
	host_input.position = Vector2(10, 40)
	host_input.size = Vector2(300, 30)
	ui.add_child(host_input)
	
	var port_input = LineEdit.new()
	port_input.text = "443"
	port_input.placeholder_text = "Port"
	port_input.position = Vector2(320, 40)
	port_input.size = Vector2(80, 30)
	ui.add_child(port_input)
	
	var connect_btn = Button.new()
	connect_btn.text = "Connect"
	connect_btn.position = Vector2(410, 40)
	connect_btn.size = Vector2(100, 30)
	connect_btn.pressed.connect(func():
		Net.connect_client(host_input.text, int(port_input.text))
		ui.visible = false
	)
	ui.add_child(connect_btn)
	# END CONNECTION UI
	
	var title = Label.new()
	title.text = "CLIENT - WASD=Move, Mouse=Aim, LMB=Shoot, RMB=Build, SPACE=Dash, SHIFT=Sprint, R=Reload, 1/2/3=Switch Weapon"
	title.position = Vector2(10, 10)
	canvas_layer.add_child(title)
	
	# Debug overlay (top-right)
	_debug_label = Label.new()
	_debug_label.position = Vector2(DisplayServer.window_get_size().x - 300, 10)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.modulate = Color(1, 1, 0, 0.9)  # Yellow
	_debug_label.visible = false
	canvas_layer.add_child(_debug_label)
	
	# Ammo HUD (bottom-right)
	_ammo_label = Label.new()
	_ammo_label.position = Vector2(DisplayServer.window_get_size().x - 200, DisplayServer.window_get_size().y - 80)
	_ammo_label.add_theme_font_size_override("font_size", 24)
	_ammo_label.modulate = Color(1, 1, 1, 1)
	canvas_layer.add_child(_ammo_label)
	
	Net.client_connected.connect(func(id): 
		_my_id = id
		Log.network("My ID is %d" % id)
	)
	Net.spawn_received.connect(_on_spawn_player)
	Net.despawn_received.connect(_on_despawn_player)
	Net.snapshot_received.connect(_on_snapshot)
	Net.ack_received.connect(_on_ack)
	Net.static_snapshot_received.connect(_on_static_snapshot)

# Main client tick: Predict local player, interpolate remote entities
func _physics_process(_delta: float) -> void:
	
	if _my_id == 0:
		return
	
	var dt = GameConstants.FIXED_DELTA
	
	# Update camera to follow local player
	if _players.has(_my_id):
		var player = _players[_my_id]
		_camera.global_position = player.global_position
		_update_ammo_hud(player)
	
	# Local prediction
	if _players.has(_my_id):
		_send_and_predict(dt)
	
	# Interpolate ALL non-local entities (players, enemies, NOT walls)
	_interpolate_all_entities()

func _process(delta: float) -> void:
	# Toggle debug overlay with F3
	if Input.is_action_just_pressed("ui_page_up"):  # F3 mapped in project settings
		_debug_visible = !_debug_visible
		_debug_label.visible = _debug_visible
	
	if _debug_visible:
		_update_debug_overlay(delta)

# Update debug overlay with network stats
func _update_debug_overlay(delta: float) -> void:
	# Track FPS
	_fps_samples.append(1.0 / delta)
	if _fps_samples.size() > 60:
		_fps_samples.pop_front()
	
	var avg_fps = 0.0
	for fps in _fps_samples:
		avg_fps += fps
	avg_fps /= _fps_samples.size()
	
	# Track SPS
	_sps_samples.append(_sps_latest_ms)
	if _sps_samples.size() > 60:
		_sps_samples.pop_front()
	
	var avg_sps = 0.0
	for sps in _sps_samples:
		avg_sps += sps
		
	var num_sps_samp = _sps_samples.size()
	if num_sps_samp == 0:
		avg_sps = 1000
	else:
		avg_sps /= num_sps_samp
	
	# Calculate packet loss (snapshots)
	var expected_snapshots = int((Time.get_ticks_msec() - _last_snapshot_time) / (1000.0 / GameConstants.PHYSICS_FPS))
	var snapshot_loss = 0.0
	var snapshot_recv = 100.0
	if expected_snapshots > 0:
		snapshot_recv = clamp(float(_snapshot_count) / float(expected_snapshots) * 100.0, 0.0, 100.0)
		snapshot_loss = 100.0 - snapshot_recv
		
	# Entity counts
	var interp_count = 0
	for net_id in _snap_buffers:
		var entity = Replication.get_entity(net_id)
		if entity and not (entity is Bullet or entity is Wall):
			interp_count += 1
	
	# Build debug text
	var text = ""
	text += "FPS: %d\n" % int(avg_fps)
	text += "Tick: %d ms\n" % int(avg_sps)
	text += "Ping: %d ms\n" % int(_ping_ms)
	text += "Snapshots: %d/%d (%.1f%% loss)\n" % [_snapshot_count, expected_snapshots, snapshot_loss]
	text += "Reconciles/sec: %d\n" % _reconcile_count
	text += "Entities: %d (Total) %d (Interp)\n" % [Replication._entities.size(), interp_count]
	text += "Pending Inputs: %d\n" % _pending_inputs.size()
	text += "Buffer Size: %d ticks" % (_snap_buffers.get(_my_id, []).size() if _my_id > 0 else 0)
	
	_debug_label.text = text
	
	# Reset per-second counters
	var now = Time.get_ticks_msec()
	if now - _last_snapshot_time >= 1000:
		_snapshot_count = 0
		_reconcile_count = 0
		_last_snapshot_time = now

# Sample input, send to server, predict movement locally, store for reconciliation
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
	if Input.is_action_pressed("ui_dash"):
		btn |= GameConstants.BTN_DASH
	if Input.is_key_pressed(KEY_SHIFT):
		btn |= GameConstants.BTN_SPRINT
	if Input.is_key_pressed(KEY_R):
		btn |= GameConstants.BTN_RELOAD
	if Input.is_key_pressed(KEY_1):
		btn |= GameConstants.BTN_SWITCH_1
	if Input.is_key_pressed(KEY_2):
		btn |= GameConstants.BTN_SWITCH_2
	if Input.is_key_pressed(KEY_3):
		btn |= GameConstants.BTN_SWITCH_3
	
	_input_seq += 1
	var cmd = {"seq": _input_seq, "mv": mv, "aim": aim, "btn": btn}
	
	# Send all inputs (idle optimization disabled)
	if _input_seq % 10 == 0:
		_last_ping_send = Time.get_ticks_msec()
	Net.server_receive_input.rpc_id(1, cmd)
	
	# CLIENT-SIDE PREDICTION: Spawn bullet immediately for instant feedback
	if btn & GameConstants.BTN_SHOOT and player.shoot():
		# Get weapon damage for client-side bullet
		var weapon_damage = GameConstants.BULLET_DAMAGE
		if player.equipped_weapon:
			weapon_damage = player.equipped_weapon.data.get("damage", GameConstants.BULLET_DAMAGE)
		
		# Spawn pellets for shotguns
		var pellets = 1
		var spread = 0.0
		if player.equipped_weapon:
			pellets = player.equipped_weapon.data.get("pellets", 1)
			spread = player.equipped_weapon.data.get("spread", 0.0)
		
		for i in range(pellets):
			var spread_angle = randf_range(-spread, spread)
			var fire_dir = aim.rotated(spread_angle)
			_spawn_predicted_bullet(player.global_position, fire_dir, weapon_damage)
	
	# Predict locally
	player.apply_input(mv, aim, btn, dt)
	
	# Store for reconciliation
	_pending_inputs.append(cmd)
	_predicted_states[_input_seq] = player.get_replicated_state()
	
	if _pending_inputs.size() > 256:
		_pending_inputs.pop_front()

#Interpolate all non-local entities (remote players, enemies) between buffered snapshots.
#Renders entities 2 ticks behind to ensure smooth interpolation even with jitter.
#Skips local player (predicted), bullets (client-predicted), and walls (static).
func _interpolate_all_entities() -> void:
	
	var render_tick = _latest_tick - GameConstants.INTERP_DELAY_TICKS
	if render_tick <= 0:
		return
	
	# Interpolate all entities with snapshot buffers (EXCEPT bullets and walls)
	for net_id in _snap_buffers:
		var entity = Replication.get_entity(net_id)
		if not entity or not is_instance_valid(entity):
			continue
		
		# Skip local player (we predict it)
		if entity is Player and entity.net_id == _my_id:
			continue
		
		# Skip bullets (they use pure client-side prediction)
		if entity is Bullet:
			continue
		
		# Skip walls (they're static, handled directly in snapshot)
		if entity is Wall:
			continue
		
		_interpolate_entity(entity, render_tick)

#Interpolate a single entity's position/rotation between two snapshots.
#Finds the two snapshots surrounding render_tick, calculates interpolation factor,
#and smoothly lerps position and rotation. Non-interpolated values (health) applied directly.
func _interpolate_entity(entity: NetworkedEntity, render_tick: int) -> void:

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
	
	# Apply non-interpolated values (health, stamina, etc.) using apply_replicated_state
	# This ensures hurt flash triggers correctly on health decrease
	if sb.has("h") and "health" in entity:
		var new_health = sb["h"]
		if entity is Player or entity is Enemy:
			# For entities with hurt flash, check if health decreased
			if new_health < entity.health:
				entity._hurt_flash_timer = 0.2
		entity.health = new_health
	
	if sb.has("v") and "velocity" in entity:
		entity.velocity = sb["v"]
	
	if sb.has("s") and "stamina" in entity:
		entity.stamina = sb["s"]
	
	# For enemies, apply full replicated state (includes custom fields like sniper aiming)
	if entity is Enemy:
		entity.apply_replicated_state(sb)

#Handle player spawn RPC from server.
#Creates Player entity, marks as local if it's our player, initializes interpolation buffer.
#Local player gets client-side prediction authority, remote players are server-authoritative.
func _on_spawn_player(payload: Dictionary) -> void:

	var peer_id = payload["peer_id"]
	
	Log.entity("Received spawn for player %d" % peer_id)
	
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
	
	Log.entity("Spawned player %d at %v" % [peer_id, player.global_position])
	
	if not _snap_buffers.has(peer_id):
		_snap_buffers[peer_id] = []

#Handle player disconnect - remove entity and clean up buffers.

func _on_despawn_player(peer_id: int) -> void:
	Log.entity("Despawning player %d" % peer_id)
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)
	_snap_buffers.erase(peer_id)

#Handle server snapshot containing all entity states.
#For LOCAL PLAYER:
  #- Store state for reconciliation
  #- Apply non-predicted state (health) immediately
  #- Trigger hurt flash if health decreased
#For WALLS (static entities):
  #- Apply health only (position is static after spawn)
  #- Skip interpolation buffer
#For REMOTE ENTITIES (players, enemies):
  #- Add to interpolation buffer
  #- Skip bullets (they're client-predicted)
func _on_snapshot(snap: Dictionary) -> void:
	_snapshot_count += 1
	
	# Measure dt snap
	var time_now = Time.get_ticks_msec()
	_sps_latest_ms = time_now - _last_time_snapshot
	_last_time_snapshot = time_now
	
	_latest_tick = snap.get("tick", _latest_tick)
	var states = snap.get("states", {})
	
	# DEBUG: Print snapshot contents occasionally
	if _latest_tick % 120 == 0:
		Log.snapshot("Snapshot tick %d contains entities: %s" % [_latest_tick, states.keys()])
		Log.snapshot("Registered entities: %s" % [Replication._entities.keys()])
	
	# Process all entities in snapshot (players, enemies, walls, NOT bullets)
	for net_id_str in states:
		var net_id = int(net_id_str)
		var state = states[net_id_str]
		
		# Special handling for local player
		if net_id == _my_id:
			_last_server_state = state
			
			# Apply non-predicted state immediately (health, stamina, etc.)
			var player = _players.get(_my_id)
			if player:
				var new_health = state.get("h", player.health)
				if new_health < player.health:
					player._hurt_flash_timer = 0.2  # Trigger flash on damage
				player.health = new_health
				player.stamina = state.get("s", player.stamina)
			
			continue
		
		# Skip bullets - they're purely client-side predicted
		var entity = Replication.get_entity(net_id)
		if entity and entity is Bullet:
			continue
		
		# Handle walls specially (static entities - no interpolation needed)
		if entity and entity is Wall:
			# Only update health, position is set once on spawn
			if state.has("h") and "health" in entity:
				entity.health = state["h"]
			continue
		
		# All other entities: add to interpolation buffer (players, enemies)
		if not _snap_buffers.has(net_id):
			_snap_buffers[net_id] = []
		
		var buf = _snap_buffers[net_id]
		buf.append({"tick": _latest_tick, "state": state})
		
		# Keep buffer bounded
		while buf.size() > 40:
			buf.pop_front()

#Handle server ACK - reconcile local player if position differs from server.
#Compares predicted position at ack_seq with server's authoritative position.
#If mismatch exceeds threshold:
  #1. Rewind to server state
  #2. Replay all pending inputs after ack_seq
  #3. Re-predict all states
#This fixes prediction errors while maintaining responsive local movement.
#Note: Health is NOT reconciled here - it's applied immediately in _on_snapshot.
func _on_ack(ack: Dictionary) -> void:
	_ack_count += 1
		
	# Measure ping
	if _last_ping_send > 0:
		_ping_ms = Time.get_ticks_msec() - _last_ping_send
		_last_ping_send = 0
	
		
	var ack_seq = ack.get("ack_seq", 0)
	if ack_seq <= 0 or _last_server_state.is_empty() or not _players.has(_my_id):
		return
	
	if not _predicted_states.has(ack_seq):
		_drop_confirmed(ack_seq)
		return
	
	var player = _players[_my_id]
	var predicted = _predicted_states[ack_seq]
	
	# Check if position differs (only reconcile on position mismatch)
	var pred_pos = predicted.get("p", Vector2.ZERO)
	var srv_pos = _last_server_state.get("p", Vector2.ZERO)
	
	var needs_reconcile = pred_pos.distance_to(srv_pos) >= GameConstants.RECONCILE_POSITION_THRESHOLD
	
	if not needs_reconcile:
		_drop_confirmed(ack_seq)
		return
	
	# Reconcile: rewind and replay
	_reconcile_count += 1
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

#Clean up confirmed inputs and states - server has acknowledged them
func _drop_confirmed(ack_seq: int) -> void:
	var replay = []
	for cmd in _pending_inputs:
		if cmd["seq"] > ack_seq:
			replay.append(cmd)
	_pending_inputs = replay
	
	for seq in _predicted_states.keys():
		if int(seq) <= ack_seq:
			_predicted_states.erase(seq)

#Spawn bullet immediately for instant client-side feedback.
#Client predicts bullet spawn/trajectory for zero-latency shooting.
#Server will also spawn authoritative bullet and validate damage.
func _spawn_predicted_bullet(pos: Vector2, dir: Vector2, dmg: float = GameConstants.BULLET_DAMAGE) -> void:

	var bullet = Bullet.new()
	bullet.net_id = -1  # Temporary ID for predicted bullets
	bullet.authority = _my_id
	bullet.initialize(pos, dir.normalized(), _my_id, dmg)
	_world.add_child(bullet)
	#Log.entity("Spawned predicted bullet at %v" % pos)


#Handle static snapshot - resync all walls every 5 seconds.
#Spawns missing walls and updates health on existing ones.
#Catches any desync from dropped packets or late joins.
func _on_static_snapshot(states: Dictionary) -> void:
	Log.network("Received static snapshot with %d walls" % states.size())
	
	for net_id_str in states:
		var net_id = int(net_id_str)
		var state = states[net_id_str]
		
		var wall = Replication.get_entity(net_id)
		if not wall:
			# Missing wall - spawn it
			Log.entity("Spawning missing wall %d from static snapshot" % net_id)
			wall = Wall.new()
			wall.net_id = net_id
			wall.authority = 1
			wall.global_position = state["pos"]
			wall.health = state["health"]
			wall.builder_id = state.get("builder", 0)
			_world.add_child(wall)
		else:
			# Update existing wall health
			if wall is Wall:
				wall.health = state["health"]


func _update_ammo_hud(player: Player) -> void:
	"""Update ammo display for local player."""
	if not player.equipped_weapon:
		_ammo_label.text = ""
		return
	
	var weapon = player.equipped_weapon
	var weapon_name = weapon.data.get("name", "Unknown")
	
	# Show ammo
	if weapon.data.get("ammo_type") == null:
		# Infinite ammo (pistol)
		_ammo_label.text = "%s: %d / ∞" % [weapon_name, weapon.ammo_loaded]
	else:
		# Normal ammo
		_ammo_label.text = "%s: %d / %d" % [weapon_name, weapon.ammo_loaded, weapon.ammo_reserve]
	
	# Show reload indicator
	if weapon.is_reloading:
		var reload_pct = int((1.0 - weapon.reload_timer / weapon.data.reload_time) * 100)
		_ammo_label.text += " [RELOADING %d%%]" % reload_pct
