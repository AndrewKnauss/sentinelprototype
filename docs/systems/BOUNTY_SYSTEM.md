# Bounty System

## Overview
Automatic bounties for killing lower-level players, escalating with repeat offenses. Bounties are claimable rewards with map markers.

## Core Data

```gdscript
# shared/BountyData.gd
class_name BountyData

var target_id: int           # Player with bounty
var value: int              # Reward amount
var kill_count: int         # Number of unfair kills
var last_kill_time: float   # Unix timestamp of last kill
var placed_by: Array[int]   # Players who placed bounties

# ServerMain.gd
var _bounties: Dictionary = {}  # player_id -> BountyData
var _kill_history: Dictionary = {}  # victim_id -> {killer_id: timestamp}
```

## Bounty Assignment

```gdscript
# ServerMain.gd
const LEVEL_DIFF_THRESHOLD = 5     # Unfair if 5+ levels higher
const BOUNTY_BASE_VALUE = 100      # Starting bounty
const BOUNTY_ESCALATION = 1.5      # Multiply per kill
const BOUNTY_COOLDOWN = 3600.0     # 1 hour between same-player kills

func _on_player_killed(victim: Player, killer: Player):
	# Skip if NPC kill or self-kill
	if killer.net_id == 0 or killer.net_id == victim.net_id:
		return
	
	# Check for repeated same-player kills (anti-farming)
	if _is_kill_farming(victim.net_id, killer.net_id):
		return
	
	# Check level difference
	var level_diff = killer.level - victim.level
	
	if level_diff >= LEVEL_DIFF_THRESHOLD:
		_add_bounty(killer.net_id, victim.net_id)

func _is_kill_farming(victim_id: int, killer_id: int) -> bool:
	if not _kill_history.has(victim_id):
		_kill_history[victim_id] = {}
	
	var victim_history = _kill_history[victim_id]
	
	# Check if killer killed victim recently
	if victim_history.has(killer_id):
		var last_kill = victim_history[killer_id]
		var time_since = Time.get_unix_time_from_system() - last_kill
		
		if time_since < BOUNTY_COOLDOWN:
			return true  # Too soon, ignore
	
	# Record this kill
	victim_history[killer_id] = Time.get_unix_time_from_system()
	return false

func _add_bounty(target_id: int, victim_id: int):
	if not _bounties.has(target_id):
		_bounties[target_id] = BountyData.new()
		_bounties[target_id].target_id = target_id
		_bounties[target_id].value = BOUNTY_BASE_VALUE
		_bounties[target_id].kill_count = 0
	
	var bounty = _bounties[target_id]
	bounty.kill_count += 1
	bounty.value = int(BOUNTY_BASE_VALUE * pow(BOUNTY_ESCALATION, bounty.kill_count - 1))
	bounty.last_kill_time = Time.get_unix_time_from_system()
	
	if not victim_id in bounty.placed_by:
		bounty.placed_by.append(victim_id)
	
	# Broadcast to all clients
	Net.client_bounty_updated.rpc({
		"target_id": target_id,
		"value": bounty.value,
		"kill_count": bounty.kill_count
	})
	
	Log.network("Bounty placed on player %d: %d credits (%d kills)" % 
		[target_id, bounty.value, bounty.kill_count])
```

## Bounty Claiming

```gdscript
# ServerMain.gd
func _on_bounty_target_killed(target: Player, killer: Player):
	if not _bounties.has(target.net_id):
		return  # No bounty
	
	var bounty = _bounties[target.net_id]
	
	# Award bounty to killer
	_award_bounty(killer, bounty.value)
	
	# Remove bounty
	_bounties.erase(target.net_id)
	
	# Broadcast removal
	Net.client_bounty_removed.rpc(target.net_id)

func _award_bounty(player: Player, amount: int):
	player.add_currency(amount)
	
	# Visual notification
	Net.client_show_notification.rpc_id(player.net_id, {
		"type": "bounty_claimed",
		"amount": amount
	})
```

## Decay System

```gdscript
# ServerMain.gd
const BOUNTY_DECAY_TIME = 1800.0  # 30 minutes no kills = decay
const BOUNTY_DECAY_RATE = 0.5     # Reduce by 50% each decay

func _physics_process(delta):
	# ... existing code
	_tick_bounties(delta)

func _tick_bounties(_delta: float):
	var current_time = Time.get_unix_time_from_system()
	var to_remove: Array[int] = []
	
	for target_id in _bounties:
		var bounty = _bounties[target_id]
		var time_since = current_time - bounty.last_kill_time
		
		if time_since >= BOUNTY_DECAY_TIME:
			# Decay bounty value
			bounty.value = int(bounty.value * BOUNTY_DECAY_RATE)
			bounty.last_kill_time = current_time
			
			if bounty.value < BOUNTY_BASE_VALUE:
				# Bounty too low, remove
				to_remove.append(target_id)
			else:
				# Broadcast decay
				Net.client_bounty_updated.rpc({
					"target_id": target_id,
					"value": bounty.value,
					"kill_count": bounty.kill_count
				})
	
	# Clean up expired bounties
	for target_id in to_remove:
		_bounties.erase(target_id)
		Net.client_bounty_removed.rpc(target_id)
```

## Client UI

```gdscript
# client/BountyMarker.gd
class_name BountyMarker extends Control

var target_id: int
var bounty_value: int
var world_pos: Vector2

func _ready():
	# Create UI elements
	var panel = PanelContainer.new()
	add_child(panel)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	var skull = TextureRect.new()
	skull.texture = preload("res://assets/skull_icon.png")
	vbox.add_child(skull)
	
	var label = Label.new()
	label.text = "%d credits" % bounty_value
	label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(label)

func _process(_delta):
	# Update position relative to camera
	var player = Replication.get_entity(target_id)
	if not player:
		queue_free()
		return
	
	world_pos = player.global_position
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		var screen_pos = camera.get_screen_center_position() + (world_pos - camera.global_position)
		position = screen_pos - (size / 2)

# ClientMain.gd
var _bounty_markers: Dictionary = {}  # target_id -> BountyMarker

func _on_bounty_updated(data: Dictionary):
	var target_id = data.target_id
	
	# Update or create marker
	if _bounty_markers.has(target_id):
		_bounty_markers[target_id].bounty_value = data.value
	else:
		var marker = BountyMarker.new()
		marker.target_id = target_id
		marker.bounty_value = data.value
		_hud.add_child(marker)
		_bounty_markers[target_id] = marker

func _on_bounty_removed(target_id: int):
	if _bounty_markers.has(target_id):
		_bounty_markers[target_id].queue_free()
		_bounty_markers.erase(target_id)
```

## Minimap Integration

```gdscript
# client/Minimap.gd
func _draw_bounty_markers():
	for target_id in ClientMain._bounty_markers:
		var player = Replication.get_entity(target_id)
		if not player:
			continue
		
		var map_pos = _world_to_map_pos(player.global_position)
		
		# Draw skull icon
		draw_texture_rect(
			skull_icon,
			Rect2(map_pos - Vector2(8, 8), Vector2(16, 16)),
			false,
			Color.RED
		)
```

## Notification System

```gdscript
# client/NotificationManager.gd (autoload)
func show_notification(data: Dictionary):
	match data.type:
		"bounty_claimed":
			_show_bounty_claimed(data.amount)
		"bounty_placed_on_you":
			_show_bounty_warning(data.value)

func _show_bounty_claimed(amount: int):
	var panel = _create_notification_panel()
	var label = Label.new()
	label.text = "Bounty Claimed: %d Credits!" % amount
	label.add_theme_color_override("font_color", Color.GOLD)
	panel.add_child(label)
	
	# Fade out after 3 seconds
	await get_tree().create_timer(3.0).timeout
	panel.queue_free()

func _show_bounty_warning(value: int):
	var panel = _create_notification_panel()
	var label = Label.new()
	label.text = "BOUNTY PLACED ON YOU: %d Credits" % value
	label.add_theme_color_override("font_color", Color.RED)
	panel.add_child(label)
	
	# Stays visible longer
	await get_tree().create_timer(5.0).timeout
	panel.queue_free()
```

## Implementation Steps

1. Add level system to Player (XP + level calculation)
2. Implement bounty tracking in ServerMain
3. Add kill history anti-farming checks
4. Create bounty marker UI elements
5. Integrate with minimap
6. Add notification system
7. Implement decay mechanics

## Balance Values

```gdscript
# shared/BountyConfig.gd
const LEVEL_DIFF_THRESHOLD = 5     # 5+ levels = griefing
const BOUNTY_BASE_VALUE = 100      # Starting reward
const BOUNTY_ESCALATION = 1.5      # +50% per additional kill
const BOUNTY_COOLDOWN = 3600.0     # 1 hour same-player cooldown
const BOUNTY_DECAY_TIME = 1800.0   # 30 min no kills = decay
const BOUNTY_DECAY_RATE = 0.5      # -50% per decay tick
const BOUNTY_MIN_VALUE = 50        # Remove if below this
```

## Edge Cases

**Problem**: Bounty farming (friends killing each other)  
**Solution**: `BOUNTY_COOLDOWN` prevents same-player kills counting

**Problem**: High-level player instantly killed by bounty hunters  
**Solution**: Display bounty marker only after 30 seconds

**Problem**: Bounty persists after logout  
**Solution**: Store in database, restore on login

## Testing Checklist
- [ ] Bounty triggers on level-diff kills
- [ ] Same-player kills ignored within cooldown
- [ ] Escalation increases value correctly
- [ ] Bounty markers appear on HUD
- [ ] Minimap shows bounty icons
- [ ] Claiming awards currency
- [ ] Decay reduces value over time
- [ ] Notifications display properly
