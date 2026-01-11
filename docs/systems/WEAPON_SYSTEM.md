# Weapon System

## Overview
Multiple weapon types with distinct stats, behaviors, and tactical roles. Inventory-based switching, ammo management, and recoil mechanics.

---

## Weapon Types

### 1. Pistol (Starter)
**Role**: Backup, infinite ammo  
**Stats**: Low damage, fast fire rate, perfect accuracy

```gdscript
# shared/WeaponData.gd
const PISTOL = {
	"id": "pistol",
	"damage": 15.0,
	"fire_rate": 0.25,  # 4 shots/sec
	"bullet_speed": 600.0,
	"spread": 0.0,  # Perfect accuracy
	"recoil": 2.0,
	"ammo_type": null,  # Infinite ammo
	"mag_size": 12,
	"reload_time": 1.5
}
```

### 2. Rifle (Balanced)
**Role**: General purpose, medium range  
**Stats**: Moderate damage/fire rate, slight spread

```gdscript
const RIFLE = {
	"id": "rifle",
	"damage": 25.0,
	"fire_rate": 0.12,  # 8.3 shots/sec
	"bullet_speed": 800.0,
	"spread": 0.05,  # Small cone
	"recoil": 5.0,
	"ammo_type": "rifle_ammo",
	"mag_size": 30,
	"reload_time": 2.0
}
```

### 3. Shotgun (Close Range)
**Role**: High burst, room clearing  
**Stats**: Multi-pellet, wide spread, slow fire

```gdscript
const SHOTGUN = {
	"id": "shotgun",
	"damage": 12.0,  # Per pellet
	"pellets": 8,  # Total damage: 96
	"fire_rate": 0.8,  # 1.25 shots/sec
	"bullet_speed": 500.0,
	"spread": 0.3,  # Wide cone
	"recoil": 15.0,
	"ammo_type": "shotgun_shells",
	"mag_size": 6,
	"reload_time": 3.0
}
```

### 4. Sniper (Long Range)
**Role**: High damage, scope zoom  
**Stats**: One-shot potential, bolt-action

```gdscript
const SNIPER = {
	"id": "sniper",
	"damage": 80.0,
	"fire_rate": 1.5,  # 0.67 shots/sec
	"bullet_speed": 1200.0,
	"spread": 0.0,  # Perfect when scoped
	"spread_hip": 0.2,  # Inaccurate hip-fire
	"recoil": 20.0,
	"ammo_type": "sniper_rounds",
	"mag_size": 5,
	"reload_time": 2.5,
	"zoom_level": 3.0
}
```

### 5. SMG (High Fire Rate)
**Role**: Spray and pray, mobility  
**Stats**: Low damage, extremely fast fire

```gdscript
const SMG = {
	"id": "smg",
	"damage": 12.0,
	"fire_rate": 0.08,  # 12.5 shots/sec
	"bullet_speed": 600.0,
	"spread": 0.1,
	"recoil": 3.0,
	"ammo_type": "smg_ammo",
	"mag_size": 40,
	"reload_time": 1.8
}
```

---

## Weapon Component

```gdscript
# entities/Weapon.gd
class_name Weapon extends Node

var data: Dictionary  # WeaponData definition
var ammo_loaded: int = 0
var ammo_reserve: int = 0
var fire_cooldown: float = 0.0
var reload_timer: float = 0.0
var is_reloading: bool = false

func _ready():
	ammo_loaded = data.get("mag_size", 0)

func can_shoot() -> bool:
	return not is_reloading and fire_cooldown <= 0 and ammo_loaded > 0

func shoot() -> bool:
	if not can_shoot():
		return false
	
	ammo_loaded -= 1
	fire_cooldown = data.fire_rate
	
	# Auto-reload on empty
	if ammo_loaded == 0 and ammo_reserve > 0:
		start_reload()
	
	return true

func start_reload():
	if is_reloading or ammo_loaded == data.mag_size:
		return
	
	is_reloading = true
	reload_timer = data.reload_time

func tick(delta: float):
	fire_cooldown -= delta
	
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0:
			_complete_reload()

func _complete_reload():
	var needed = data.mag_size - ammo_loaded
	var to_load = min(needed, ammo_reserve)
	
	ammo_loaded += to_load
	ammo_reserve -= to_load
	is_reloading = false
```

---

## Player Integration

```gdscript
# entities/Player.gd
var equipped_weapon: Weapon = null
var inventory_weapons: Array[Weapon] = []  # Up to 3 slots

func _ready():
	super._ready()
	
	# Start with pistol
	var pistol = Weapon.new()
	pistol.data = WeaponData.PISTOL
	pistol.ammo_reserve = 999  # Infinite
	add_child(pistol)
	inventory_weapons.append(pistol)
	equipped_weapon = pistol

func apply_input(mv: Vector2, aim: Vector2, buttons: int, dt: float):
	# ... existing movement code
	
	# Weapon tick
	if equipped_weapon:
		equipped_weapon.tick(dt)
	
	# Shooting
	if buttons & GameConstants.BTN_SHOOT:
		if equipped_weapon and equipped_weapon.shoot():
			_fire_weapon(aim)
	
	# Reload
	if buttons & GameConstants.BTN_RELOAD:
		if equipped_weapon:
			equipped_weapon.start_reload()

func _fire_weapon(aim: Vector2):
	var weapon_data = equipped_weapon.data
	var pellets = weapon_data.get("pellets", 1)
	
	for i in range(pellets):
		var spread = weapon_data.get("spread", 0.0)
		var spread_angle = randf_range(-spread, spread)
		var fire_dir = aim.rotated(spread_angle)
		
		# Emit signal for server to spawn bullet
		wants_to_shoot.emit(fire_dir, weapon_data.damage)
```

---

## Recoil System

```gdscript
# ClientMain.gd
var _recoil_offset: Vector2 = Vector2.ZERO
var _recoil_recovery: float = 10.0  # Units per second

func _on_weapon_fired(recoil: float):
	# Add random recoil
	var angle = randf_range(-PI/4, PI/4)
	_recoil_offset += Vector2(0, -recoil).rotated(angle)

func _process(delta):
	# ... existing code
	
	# Recover from recoil
	_recoil_offset = _recoil_offset.lerp(Vector2.ZERO, _recoil_recovery * delta)
	
	# Apply to camera
	if _camera:
		_camera.offset = _recoil_offset
```

---

## Weapon Switching

```gdscript
# ClientMain.gd
const BTN_SWITCH_1 = 16
const BTN_SWITCH_2 = 32
const BTN_SWITCH_3 = 64

func _send_and_predict(dt: float):
	# ... existing input
	
	if Input.is_action_just_pressed("weapon_1"):
		btn |= BTN_SWITCH_1
	if Input.is_action_just_pressed("weapon_2"):
		btn |= BTN_SWITCH_2
	if Input.is_action_just_pressed("weapon_3"):
		btn |= BTN_SWITCH_3

# Player.gd
func apply_input(mv, aim, buttons, dt):
	# ... existing code
	
	# Weapon switching
	if buttons & BTN_SWITCH_1 and inventory_weapons.size() > 0:
		equipped_weapon = inventory_weapons[0]
	elif buttons & BTN_SWITCH_2 and inventory_weapons.size() > 1:
		equipped_weapon = inventory_weapons[1]
	elif buttons & BTN_SWITCH_3 and inventory_weapons.size() > 2:
		equipped_weapon = inventory_weapons[2]
```

---

## Ammo Pickup

```gdscript
# entities/AmmoBox.gd
class_name AmmoBox extends NetworkedEntity

var ammo_type: String = "rifle_ammo"
var quantity: int = 30

func _on_pickup(player: Player):
	# Find weapon that uses this ammo
	for weapon in player.inventory_weapons:
		if weapon.data.get("ammo_type") == ammo_type:
			weapon.ammo_reserve += quantity
			return true
	
	return false  # No weapon uses this ammo
```

---

## UI Elements

```gdscript
# client/WeaponHUD.gd
class_name WeaponHUD extends Control

var ammo_label: Label
var weapon_icon: TextureRect
var reload_bar: ProgressBar

func update_display(weapon: Weapon):
	if not weapon:
		visible = false
		return
	
	visible = true
	
	# Ammo counter
	if weapon.data.ammo_type == null:
		ammo_label.text = "∞"  # Infinite
	else:
		ammo_label.text = "%d / %d" % [weapon.ammo_loaded, weapon.ammo_reserve]
	
	# Reload bar
	if weapon.is_reloading:
		reload_bar.visible = true
		reload_bar.value = (weapon.data.reload_time - weapon.reload_timer) / weapon.data.reload_time
	else:
		reload_bar.visible = false
	
	# Weapon icon
	weapon_icon.texture = _get_weapon_icon(weapon.data.id)
```

---

## Network Sync

```gdscript
# Player.gd
func get_replicated_state() -> Dictionary:
	return {
		"p": global_position,
		"r": rotation,
		"h": health,
		"v": velocity,
		"w": equipped_weapon.data.id if equipped_weapon else "",
		"a": equipped_weapon.ammo_loaded if equipped_weapon else 0
	}

func apply_replicated_state(state: Dictionary):
	# ... existing state application
	
	var weapon_id = state.get("w", "")
	if weapon_id != "" and equipped_weapon.data.id != weapon_id:
		_switch_to_weapon(weapon_id)
	
	if equipped_weapon:
		equipped_weapon.ammo_loaded = state.get("a", 0)
```

---

## Implementation Steps

1. Create WeaponData definitions
2. Add Weapon component class
3. Integrate with Player (shoot/reload)
4. Add recoil to camera
5. Implement weapon switching (1/2/3 keys)
6. Create AmmoBox entity
7. Build weapon HUD
8. Network sync weapon state

---

## Balance Tuning

```gdscript
# shared/WeaponBalance.gd
const DAMAGE_MULTIPLIERS = {
	"pistol": 1.0,
	"rifle": 1.0,
	"shotgun": 1.2,  # Slight buff
	"sniper": 1.0,
	"smg": 0.9  # Slight nerf
}

const ENEMY_RESISTANCES = {
	"scout": {"pistol": 1.0, "rifle": 1.0, "shotgun": 0.7, "sniper": 1.2},
	"tank": {"pistol": 0.5, "rifle": 0.7, "shotgun": 0.9, "sniper": 1.0},
	# ... etc
}
```

---

## Testing Checklist

- [ ] All weapons fire at correct rate
- [ ] Ammo depletes/reloads properly
- [ ] Shotgun spawns multiple pellets
- [ ] Recoil feels responsive
- [ ] Weapon switching is instant
- [ ] Sniper zoom works
- [ ] Network sync doesn't lag
- [ ] Ammo pickups grant correct amounts
