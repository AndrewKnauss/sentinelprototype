extends NetworkedEntity
class_name Player

# =============================================================================
# Player.gd
# =============================================================================
# Networked player entity with movement, shooting, and building.
# =============================================================================

var health: float = GameConstants.PLAYER_MAX_HEALTH
var velocity: Vector2 = Vector2.ZERO
var is_local: bool = false

var _shoot_cooldown: float = 0.0
var _dash_timer: float = 0.0  # Active dash time
var _dash_cooldown: float = 0.0  # Time until next dash
var _dash_direction: Vector2 = Vector2.ZERO  # Direction of current dash
var stamina: float = GameConstants.PLAYER_STAMINA_MAX
var is_sprinting: bool = false

# Weapon system
var equipped_weapon: Weapon = null
var inventory_weapons: Array = []  # Up to 3 weapons

var _sprite: Sprite2D
var _label: Label
var _health_bar: ColorRect
var _stamina_bar: ColorRect
var _hurt_flash_timer: float = 0.0

static var _shared_tex: Texture2D = null


func _ready() -> void:
	super._ready()
	entity_type = "player"
	
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
	_label.text = str(net_id)
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
	_stamina_bar.visible = false  # Hide when full
	add_child(_stamina_bar)
	
	# Setup starting weapon (pistol)
	var pistol = Weapon.new()
	pistol.data = WeaponData.PISTOL
	add_child(pistol)
	inventory_weapons.append(pistol)
	equipped_weapon = pistol
	
	# Add rifle for testing
	var rifle = Weapon.new()
	rifle.data = WeaponData.RIFLE
	rifle.ammo_reserve = 120  # 4 mags
	add_child(rifle)
	inventory_weapons.append(rifle)
	
	# Add shotgun for testing
	var shotgun = Weapon.new()
	shotgun.data = WeaponData.SHOTGUN
	shotgun.ammo_reserve = 24  # 4 mags
	add_child(shotgun)
	inventory_weapons.append(shotgun)


func _process(delta: float) -> void:
	_shoot_cooldown -= delta
	_dash_timer -= delta
	_dash_cooldown -= delta
	_update_health_bar()
	_update_stamina_bar()
	
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
		# Start dash
		_dash_timer = GameConstants.PLAYER_DASH_DURATION
		_dash_cooldown = GameConstants.PLAYER_DASH_COOLDOWN
		_dash_direction = mv.normalized()
	
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
	
	# Apply movement (dash > sprint > normal)
	if _dash_timer > 0.0:
		velocity = _dash_direction * GameConstants.PLAYER_DASH_SPEED
	elif is_sprinting:
		velocity = mv * GameConstants.PLAYER_SPRINT_SPEED
	else:
		velocity = mv * GameConstants.PLAYER_MOVE_SPEED
	
	global_position += velocity * dt
	
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
	_hurt_flash_timer = 0.2  # Flash red for 0.2 seconds
	if health <= 0:
		health = 0
		return true
	return false


func respawn(pos: Vector2) -> void:
	"""Respawn at position with full health."""
	health = GameConstants.PLAYER_MAX_HEALTH
	global_position = pos
	velocity = Vector2.ZERO


func get_replicated_state() -> Dictionary:
	var weapon_state = equipped_weapon.get_state() if equipped_weapon else {"id": "pistol", "loaded": 12, "reserve": 999, "reloading": false}
	return {
		"p": global_position,
		"r": rotation,
		"h": health,
		"v": velocity,
		"s": stamina,
		"w": weapon_state
	}


func apply_replicated_state(state: Dictionary) -> void:
	global_position = state.get("p", global_position)
	rotation = state.get("r", rotation)
	
	# Check if health decreased (took damage)
	var new_health = state.get("h", health)
	if new_health < health:
		_hurt_flash_timer = 0.2  # Trigger flash on health drop
	health = new_health
	
	velocity = state.get("v", velocity)
	stamina = state.get("s", stamina)
	
	# Apply weapon state
	if equipped_weapon and state.has("w"):
		equipped_weapon.apply_state(state["w"])


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
	_stamina_bar.visible = pct < 1.0  # Hide when full


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
