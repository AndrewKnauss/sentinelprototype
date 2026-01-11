extends Node
class_name Weapon

# =============================================================================
# Weapon.gd
# =============================================================================
# Weapon component attached to Player. Handles ammo, reloading, fire cooldown.
# =============================================================================

var data: Dictionary = WeaponData.PISTOL
var ammo_loaded: int = 0
var ammo_reserve: int = 0
var fire_cooldown: float = 0.0
var reload_timer: float = 0.0
var is_reloading: bool = false


func _ready() -> void:
	ammo_loaded = data.get("mag_size", 12)
	
	# Infinite ammo for weapons without ammo_type (pistol)
	if data.get("ammo_type") == null:
		ammo_reserve = 999


func can_shoot() -> bool:
	return not is_reloading and fire_cooldown <= 0.0 and ammo_loaded > 0


func shoot() -> bool:
	"""Attempt to fire. Returns true if shot was fired."""
	if not can_shoot():
		return false
	
	ammo_loaded -= 1
	fire_cooldown = data.fire_rate
	
	# Auto-reload on empty
	if ammo_loaded == 0 and ammo_reserve > 0:
		start_reload()
	
	return true


func start_reload() -> void:
	"""Begin reload if possible."""
	if is_reloading or ammo_loaded >= data.mag_size or ammo_reserve <= 0:
		return
	
	is_reloading = true
	reload_timer = data.reload_time


func tick(delta: float) -> void:
	"""Update timers."""
	fire_cooldown = max(0.0, fire_cooldown - delta)
	
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_complete_reload()


func _complete_reload() -> void:
	"""Finish reload - transfer ammo from reserve to mag."""
	var needed = data.mag_size - ammo_loaded
	var to_load = min(needed, ammo_reserve)
	
	ammo_loaded += to_load
	ammo_reserve -= to_load
	is_reloading = false
	reload_timer = 0.0


func get_state() -> Dictionary:
	"""For network sync."""
	return {
		"id": data.id,
		"loaded": ammo_loaded,
		"reserve": ammo_reserve,
		"reloading": is_reloading
	}


func apply_state(state: Dictionary) -> void:
	"""Apply networked state."""
	var weapon_id = state.get("id", "pistol")
	if weapon_id != data.id:
		data = WeaponData.get_weapon(weapon_id)
	
	ammo_loaded = state.get("loaded", ammo_loaded)
	ammo_reserve = state.get("reserve", ammo_reserve)
	is_reloading = state.get("reloading", false)
