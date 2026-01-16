extends CharacterBody2D
class_name Player

# =============================================================================
# Player.gd - REFACTORED TO EXTEND CharacterBody2D
# =============================================================================
# Networked player entity with movement, shooting, and building.
# Uses NetworkedEntity component for replication.
# =============================================================================

signal dropped_loot(position: Vector2, loot_items: Array)  # Emitted when player dies

# Networking component
var net_entity: NetworkedEntity = null
var net_id: int = 0
var authority: int = 1
var is_local: bool = false

# Player stats
var health: float = GameConstants.PLAYER_MAX_HEALTH
var username: String = ""
var stamina: float = GameConstants.PLAYER_STAMINA_MAX
var is_sprinting: bool = false

# Movement state
var _dash_timer: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO

# Weapon system
var equipped_weapon: Weapon = null
var inventory_weapons: Array = []

# Inventory system
var inventory: Inventory = null

# Visuals
var _sprite: Sprite2D
var _label: Label
var _health_bar: ColorRect
var _stamina_bar: ColorRect
var _hurt_flash_timer: float = 0.0

static var _shared_tex: Texture2D = null


func _ready() -> void:
	# Create networking component
	net_entity = NetworkedEntity.new(self, net_id, authority, "player")
	
	# Setup collision
	collision_layer = 2      # Layer 2 = PLAYER
	collision_mask = 1 | 2   # Collide with STATIC + PLAYER
	
	# Add collision shape
	var shape_node = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 8.0
	shape_node.shape = circle
	add_child(shape_node)
	
	# Create shared texture once
	if _shared_tex == null:
		var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_shared_tex = ImageTexture.create_from_image(img)
	
	# Visual setup
	_sprite = Sprite2D.new()
	_sprite.texture = _shared_tex
	_sprite.centered = true
	var color = Color.BLACK if is_local else _color_from_id(net_id)
	_sprite.modulate = color
	add_child(_sprite)
	
	_label = Label.new()
	_label.text = username if not username.is_empty() else str(net_id)
	_label.position = Vector2(-10, -26)
	_label.scale = Vector2(0.8, 0.8)
	add_child(_label)
	
	# Health bar
	_health_bar = ColorRect.new()
	_health_bar.size = Vector2(20, 3)
	_health_bar.position = Vector2(-10, -20)
	_health_bar.color = Color.GREEN
	add_child(_health_bar)
	
	# Stamina bar
	_stamina_bar = ColorRect.new()
	_stamina_bar.size = Vector2(20, 2)
	_stamina_bar.position = Vector2(-10, -17)
	_stamina_bar.color = Color.YELLOW
	_stamina_bar.visible = false
	add_child(_stamina_bar)
	
	# Create inventory
	inventory = Inventory.new()
	add_child(inventory)
	
	# Setup starting weapons
	var pistol = Weapon.new()
	pistol.data = WeaponData.PISTOL
	add_child(pistol)
	inventory_weapons.append(pistol)
	equipped_weapon = pistol
	
	var rifle = Weapon.new()
	rifle.data = WeaponData.RIFLE
	rifle.ammo_reserve = 120
	add_child(rifle)
	inventory_weapons.append(rifle)
	
	var shotgun = Weapon.new()
	shotgun.data = WeaponData.SHOTGUN
	shotgun.ammo_reserve = 24
	add_child(shotgun)
	inventory_weapons.append(shotgun)


func _exit_tree() -> void:
	if net_entity:
		net_entity.unregister()


func _process(delta: float) -> void:
	_update_health_bar()
	_update_stamina_bar()
	
	if _label and not username.is_empty() and _label.text != username:
		_label.text = username
	
	# Hurt flash effect
	if _hurt_flash_timer > 0.0:
		_hurt_flash_timer -= delta
		var flash_intensity = _hurt_flash_timer / 0.2
		_sprite.modulate = Color.RED.lerp(_get_base_color(), 1.0 - flash_intensity)
	else:
		_sprite.modulate = _get_base_color()


func apply_input(mv: Vector2, aim: Vector2, buttons: int, dt: float) -> void:
	"""Apply player input (movement and aiming)."""
	if mv.length() > 1.0:
		mv = mv.normalized()
	
	# Tick weapon cooldowns
	if equipped_weapon:
		equipped_weapon.tick(dt)
	
	# Reload
	if buttons & GameConstants.BTN_RELOAD:
		if equipped_weapon:
			equipped_weapon.start_reload()
	
	# Weapon switching
	if buttons & GameConstants.BTN_SWITCH_1 and inventory_weapons.size() > 0:
		equipped_weapon = inventory_weapons[0]
	elif buttons & GameConstants.BTN_SWITCH_2 and inventory_weapons.size() > 1:
		equipped_weapon = inventory_weapons[1]
	elif buttons & GameConstants.BTN_SWITCH_3 and inventory_weapons.size() > 2:
		equipped_weapon = inventory_weapons[2]
	
	# Handle dash
	if buttons & GameConstants.BTN_DASH and _dash_cooldown <= 0.0 and mv.length() > 0.01:
		_dash_timer = GameConstants.PLAYER_DASH_DURATION
		_dash_cooldown = GameConstants.PLAYER_DASH_COOLDOWN
		_dash_direction = mv.normalized()
	
	# Update timers
	_dash_timer -= dt
	_dash_cooldown -= dt
	
	# Handle sprint
	var wants_sprint = (buttons & GameConstants.BTN_SPRINT) and mv.length() > 0.1
	
	if wants_sprint and stamina > 0.0:
		is_sprinting = true
		stamina -= GameConstants.PLAYER_SPRINT_STAMINA_COST * dt
		if stamina < 0.0:
			stamina = 0.0
	else:
		is_sprinting = false
		stamina += GameConstants.PLAYER_STAMINA_REGEN * dt
		if stamina > GameConstants.PLAYER_STAMINA_MAX:
			stamina = GameConstants.PLAYER_STAMINA_MAX
	
	# Calculate velocity (dash > sprint > normal)
	if _dash_timer > 0.0:
		velocity = _dash_direction * GameConstants.PLAYER_DASH_SPEED
	elif is_sprinting:
		velocity = mv * GameConstants.PLAYER_SPRINT_SPEED
	else:
		velocity = mv * GameConstants.PLAYER_MOVE_SPEED
	
	# Move with collision - CLEAN AND SIMPLE!
	move_and_slide()
	
	# Clamp to world bounds
	global_position.x = clamp(global_position.x, 0, 1024)
	global_position.y = clamp(global_position.y, 0, 600)
	
	if aim.length() > 0.001:
		rotation = aim.angle()


func shoot() -> bool:
	"""Attempt to shoot. Returns true if shot was fired."""
	if equipped_weapon:
		return equipped_weapon.shoot()
	return false


func take_damage(amount: float) -> bool:
	"""Apply damage. Returns true if killed."""
	health -= amount
	_hurt_flash_timer = 0.2
	if health <= 0:
		health = 0
		# Drop all items on death
		var items = inventory.get_all_items()
		if items.size() > 0:
			dropped_loot.emit(global_position, items)
		return true
	return false


func respawn(pos: Vector2) -> void:
	"""Respawn at position with full health."""
	health = GameConstants.PLAYER_MAX_HEALTH
	global_position = pos
	velocity = Vector2.ZERO
	# Clear inventory on respawn
	inventory.clear()


func get_replicated_state() -> Dictionary:
	var weapon_state = equipped_weapon.get_state() if equipped_weapon else {"id": "pistol", "loaded": 12, "reserve": 999, "reloading": false}
	return {
		"p": global_position,
		"r": rotation,
		"h": health,
		"v": velocity,
		"s": stamina,
		"w": weapon_state,
		"u": username
	}


func apply_replicated_state(state: Dictionary) -> void:
	global_position = state.get("p", global_position)
	rotation = state.get("r", rotation)
	
	# Check if health decreased (took damage)
	var new_health = state.get("h", health)
	if new_health < health:
		_hurt_flash_timer = 0.2
	health = new_health
	
	velocity = state.get("v", velocity)
	stamina = state.get("s", stamina)
	
	# Apply weapon state
	if equipped_weapon and state.has("w"):
		equipped_weapon.apply_state(state["w"])
	
	# Apply username
	var new_username = state.get("u", "")
	if new_username != username:
		username = new_username
		if _label:
			_label.text = username if not username.is_empty() else str(net_id)


func _update_health_bar() -> void:
	var pct = health / GameConstants.PLAYER_MAX_HEALTH
	_health_bar.size.x = 20 * pct
	if pct > 0.6:
		_health_bar.color = Color.GREEN
	elif pct > 0.3:
		_health_bar.color = Color.YELLOW
	else:
		_health_bar.color = Color.RED


func _update_stamina_bar() -> void:
	var pct = stamina / GameConstants.PLAYER_STAMINA_MAX
	_stamina_bar.size.x = 20 * pct
	_stamina_bar.visible = pct < 1.0


func _color_from_id(id: int) -> Color:
	var x = id * 1103515245 + 12345
	var r = float((x >> 16) & 255) / 255.0
	x = x * 1103515245 + 12345
	var g = float((x >> 16) & 255) / 255.0
	x = x * 1103515245 + 12345
	var b = float((x >> 16) & 255) / 255.0
	return Color(0.25 + 0.75 * r, 0.25 + 0.75 * g, 0.25 + 0.75 * b, 1.0)


func _get_base_color() -> Color:
	return Color.BLACK if is_local else _color_from_id(net_id)
