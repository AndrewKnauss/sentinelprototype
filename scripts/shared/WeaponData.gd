extends Node
class_name WeaponData

# =============================================================================
# WeaponData.gd
# =============================================================================
# Weapon definitions with stats and behavior.
# =============================================================================

const PISTOL = {
	"id": "pistol",
	"name": "Pistol",
	"damage": 15.0,
	"fire_rate": 0.25,  # 4 shots/sec
	"bullet_speed": 600.0,
	"spread": 0.0,  # Perfect accuracy
	"pellets": 1,
	"ammo_type": null,  # Infinite ammo (no reserve)
	"mag_size": 12,
	"reload_time": 1.5
}

const RIFLE = {
	"id": "rifle",
	"name": "Rifle",
	"damage": 25.0,
	"fire_rate": 0.12,  # 8.3 shots/sec
	"bullet_speed": 800.0,
	"spread": 0.05,  # Small cone
	"pellets": 1,
	"ammo_type": "rifle_ammo",
	"mag_size": 30,
	"reload_time": 2.0
}

const SHOTGUN = {
	"id": "shotgun",
	"name": "Shotgun",
	"damage": 12.0,  # Per pellet
	"fire_rate": 0.8,  # 1.25 shots/sec
	"bullet_speed": 500.0,
	"spread": 0.3,  # Wide cone
	"pellets": 8,  # Total damage: 96
	"ammo_type": "shotgun_shells",
	"mag_size": 6,
	"reload_time": 3.0
}

const SNIPER = {
	"id": "sniper",
	"name": "Sniper",
	"damage": 80.0,
	"fire_rate": 1.5,  # 0.67 shots/sec
	"bullet_speed": 1200.0,
	"spread": 0.0,  # Perfect when scoped
	"pellets": 1,
	"ammo_type": "sniper_rounds",
	"mag_size": 5,
	"reload_time": 2.5
}

const SMG = {
	"id": "smg",
	"name": "SMG",
	"damage": 12.0,
	"fire_rate": 0.08,  # 12.5 shots/sec
	"bullet_speed": 600.0,
	"spread": 0.1,
	"pellets": 1,
	"ammo_type": "smg_ammo",
	"mag_size": 40,
	"reload_time": 1.8
}

# Lookup table
const WEAPONS = {
	"pistol": PISTOL,
	"rifle": RIFLE,
	"shotgun": SHOTGUN,
	"sniper": SNIPER,
	"smg": SMG
}

static func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, PISTOL)
