# Lawfulness Zones System

## Overview
Map divided into zones with varying PvP consequences: Safe (heavy penalties) → Neutral (moderate) → Lawless (none, best loot).

## Zone Types

```gdscript
# shared/ZoneData.gd
enum ZoneType { SAFE, NEUTRAL, LAWLESS }

class_name ZoneDefinition
var zone_type: ZoneType
var bounds: Rect2  # World space rectangle
var pvp_allowed: bool
var pvp_penalty: float  # Reputation loss multiplier
var loot_multiplier: float
var ai_density: float

# Example zones
const ZONES = [
	ZoneDefinition.new(ZoneType.SAFE, Rect2(0, 0, 300, 300), false, 10.0, 0.5, 0.3),
	ZoneDefinition.new(ZoneType.NEUTRAL, Rect2(300, 0, 400, 600), true, 1.0, 1.0, 1.0),
	ZoneDefinition.new(ZoneType.LAWLESS, Rect2(700, 0, 300, 600), true, 0.0, 2.0, 2.0)
]
```

## Zone Manager

```gdscript
# shared/ZoneManager.gd (autoload)
class_name ZoneManager extends Node

func get_zone_at(pos: Vector2) -> ZoneDefinition:
	for zone in ZoneData.ZONES:
		if zone.bounds.has_point(pos):
			return zone
	return null  # Outside all zones

func get_zone_type(pos: Vector2) -> ZoneType:
	var zone = get_zone_at(pos)
	return zone.zone_type if zone else ZoneType.NEUTRAL
```

## PvP Enforcement

```gdscript
# ServerMain.gd
func _on_player_attacked(attacker: Player, victim: Player, damage: float) -> bool:
	var zone = ZoneManager.get_zone_at(victim.global_position)
	
	if not zone:
		return true  # Allow by default
	
	# SAFE ZONE: Block PvP entirely
	if zone.zone_type == ZoneType.SAFE:
		# Notify attacker
		Net.client_show_notification.rpc_id(attacker.net_id, {
			"type": "pvp_blocked",
			"message": "PvP disabled in Safe Zone"
		})
		return false  # Block damage
	
	# NEUTRAL ZONE: Allow but apply reputation penalty
	if zone.zone_type == ZoneType.NEUTRAL:
		_apply_reputation_penalty(attacker, zone.pvp_penalty)
		return true
	
	# LAWLESS ZONE: No penalties
	return true

func _apply_reputation_penalty(player: Player, multiplier: float):
	var penalty = 10.0 * multiplier
	player.reputation -= penalty
	
	Net.client_show_notification.rpc_id(player.net_id, {
		"type": "reputation_loss",
		"amount": int(penalty)
	})
```

## Loot Scaling

```gdscript
# ServerMain.gd
func _spawn_item_drop(pos: Vector2, item_id: String, base_qty: int):
	var zone = ZoneManager.get_zone_at(pos)
	var multiplier = zone.loot_multiplier if zone else 1.0
	
	var qty = int(base_qty * multiplier)
	# ... rest of spawn code

# Enemy spawning
func _get_spawn_weight(pos: Vector2) -> float:
	var zone = ZoneManager.get_zone_at(pos)
	return zone.ai_density if zone else 1.0
```

## Visual Indicators

```gdscript
# client/ZoneOverlay.gd
class_name ZoneOverlay extends CanvasLayer

func _ready():
	# Create colored overlay for each zone
	for zone in ZoneData.ZONES:
		var rect = ColorRect.new()
		rect.color = _get_zone_color(zone.zone_type)
		rect.position = zone.bounds.position
		rect.size = zone.bounds.size
		add_child(rect)

func _get_zone_color(type: ZoneType) -> Color:
	match type:
		ZoneType.SAFE:
			return Color(0, 1, 0, 0.1)  # Green tint
		ZoneType.NEUTRAL:
			return Color(1, 1, 0, 0.1)  # Yellow tint
		ZoneType.LAWLESS:
			return Color(1, 0, 0, 0.1)  # Red tint
	return Color.TRANSPARENT

# client/ZoneHUD.gd
var current_zone: ZoneType

func _process(_delta):
	var player = ClientMain._players.get(ClientMain._my_id)
	if not player:
		return
	
	var zone_type = ZoneManager.get_zone_type(player.global_position)
	
	if zone_type != current_zone:
		current_zone = zone_type
		_update_zone_display()

func _update_zone_display():
	var zone_label = get_node("ZoneLabel")
	
	match current_zone:
		ZoneType.SAFE:
			zone_label.text = "SAFE ZONE"
			zone_label.modulate = Color.GREEN
		ZoneType.NEUTRAL:
			zone_label.text = "NEUTRAL ZONE"
			zone_label.modulate = Color.YELLOW
		ZoneType.LAWLESS:
			zone_label.text = "LAWLESS ZONE"
			zone_label.modulate = Color.RED
```

## Minimap Integration

```gdscript
# client/Minimap.gd
func _draw():
	# ... existing code
	
	# Draw zone boundaries
	for zone in ZoneData.ZONES:
		var map_rect = Rect2(
			_world_to_map_pos(zone.bounds.position),
			zone.bounds.size * _scale
		)
		
		draw_rect(map_rect, _get_zone_color(zone.zone_type), false, 2.0)
```

## Reputation System

```gdscript
# entities/Player.gd
var reputation: float = 0.0  # -1000 (hostile) to +1000 (hero)

const REP_HERO = 500
const REP_GOOD = 100
const REP_NEUTRAL = 0
const REP_BAD = -100
const REP_HOSTILE = -500

func get_reputation_tier() -> String:
	if reputation >= REP_HERO:
		return "Hero"
	elif reputation >= REP_GOOD:
		return "Good"
	elif reputation >= REP_NEUTRAL:
		return "Neutral"
	elif reputation >= REP_BAD:
		return "Bad"
	else:
		return "Hostile"

# ServerMain.gd - Reputation effects
func _can_enter_safe_zone(player: Player) -> bool:
	return player.reputation >= -200  # Hostile players banned

func _on_player_entered_safe_zone(player: Player):
	if not _can_enter_safe_zone(player):
		# Teleport out + damage
		player.take_damage(25.0)
		player.global_position = _get_nearest_neutral_zone()
		
		Net.client_show_notification.rpc_id(player.net_id, {
			"type": "zone_rejected",
			"message": "Hostile players cannot enter Safe Zone"
		})
```

## Border Enforcement

```gdscript
# ServerMain.gd
func _physics_process(delta):
	# ... existing code
	
	for peer_id in _players:
		var player = _players[peer_id]
		_check_zone_transitions(player)

func _check_zone_transitions(player: Player):
	var current_zone = ZoneManager.get_zone_at(player.global_position)
	var last_zone = player.get_meta("last_zone", null)
	
	if current_zone != last_zone:
		# Zone change
		_on_player_zone_changed(player, last_zone, current_zone)
		player.set_meta("last_zone", current_zone)

func _on_player_zone_changed(player: Player, from: ZoneDefinition, to: ZoneDefinition):
	# Safe zone entry check
	if to and to.zone_type == ZoneType.SAFE:
		if not _can_enter_safe_zone(player):
			_reject_zone_entry(player, from)
			return
	
	# Notify client
	Net.client_zone_changed.rpc_id(player.net_id, {
		"zone_type": to.zone_type if to else ZoneType.NEUTRAL
	})
```

## Implementation Steps

1. Define zone boundaries in ZoneData
2. Create ZoneManager autoload
3. Add PvP blocking for Safe zones
4. Implement reputation penalties
5. Scale loot by zone multiplier
6. Add visual overlays
7. Create zone HUD indicator
8. Add minimap zone borders

## Balance Tuning

```gdscript
# shared/ZoneConfig.gd
const SAFE_ZONE_REP_REQUIRED = -200
const NEUTRAL_PVP_PENALTY = 10.0
const SAFE_LOOT_MULT = 0.5
const NEUTRAL_LOOT_MULT = 1.0
const LAWLESS_LOOT_MULT = 2.0
const SAFE_AI_DENSITY = 0.3
const LAWLESS_AI_DENSITY = 2.0
```

## Edge Cases

**Problem**: Player shoots from Neutral into Safe zone  
**Solution**: Check both attacker and victim positions

**Problem**: Lawless zone becomes spawn-camping haven  
**Solution**: Respawn only in Safe/Neutral zones

**Problem**: Players farm rep in Safe zones  
**Solution**: Reduce XP/loot gains in Safe zones

## Testing Checklist
- [ ] Zone boundaries defined correctly
- [ ] PvP blocked in Safe zones
- [ ] Reputation penalties apply in Neutral
- [ ] Loot scales by zone
- [ ] Visual overlays render
- [ ] HUD shows current zone
- [ ] Minimap displays boundaries
- [ ] Hostile players rejected from Safe zones
