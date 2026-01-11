# World Events System

## Overview
Timed high-value events (supply drops, data caches, machine patrols) that drive players to contest locations for loot and objectives.

## Event Types

### 1. Supply Drop
**Frequency**: Every 10 minutes  
**Duration**: 5 minutes or until looted  
**Loot**: High-tier items, rare resources

```gdscript
# server/events/SupplyDrop.gd
class_name SupplyDropEvent extends WorldEvent

var drop_position: Vector2
var crate: SupplyCrate  # Entity containing loot

func activate():
	# Announce to all players
	Net.client_show_event_announcement.rpc({
		"type": "supply_drop",
		"message": "Supply drop incoming!",
		"position": drop_position,
		"duration": 300.0  # 5 min
	})
	
	# Spawn crate after delay
	await get_tree().create_timer(15.0).timeout  # Plane transit time
	_spawn_crate()

func _spawn_crate():
	crate = SupplyCrate.new()
	crate.net_id = Replication.generate_id()
	crate.global_position = drop_position
	crate.loot_table = SUPPLY_DROP_LOOT_TABLE
	crate.opened.connect(_on_crate_opened)
	ServerMain._world.add_child(crate)
	
	Net.spawn_entity.rpc({
		"type": "supply_crate",
		"net_id": crate.net_id,
		"pos": drop_position,
		"extra": {}
	})

func _on_crate_opened(player_id: int):
	completed.emit(player_id)
	cleanup()
```

### 2. Data Cache
**Frequency**: Every 15 minutes  
**Duration**: 10 minutes  
**Objective**: Hack terminal, download data while defending

```gdscript
# server/events/DataCacheEvent.gd
class_name DataCacheEvent extends WorldEvent

var terminal_position: Vector2
var terminal: DataTerminal
var hacker_id: int = 0
var hack_progress: float = 0.0
const HACK_DURATION = 30.0  # Seconds to complete

func activate():
	Net.client_show_event_announcement.rpc({
		"type": "data_cache",
		"message": "Data cache detected!",
		"position": terminal_position,
		"duration": 600.0
	})
	
	_spawn_terminal()

func _physics_process(delta):
	if hacker_id > 0:
		var player = ServerMain._players.get(hacker_id)
		if not player or player.global_position.distance_to(terminal_position) > 50:
			# Player left range, reset hack
			hacker_id = 0
			hack_progress = 0.0
			return
		
		hack_progress += delta
		
		if hack_progress >= HACK_DURATION:
			_complete_hack()

func _start_hack(player_id: int):
	hacker_id = player_id
	hack_progress = 0.0
	
	Net.client_update_hack_progress.rpc({
		"progress": 0.0,
		"hacker_id": player_id
	})

func _complete_hack():
	var player = ServerMain._players.get(hacker_id)
	if player:
		# Award high-value data item
		player.inventory.add_item("classified_data", 1)
	
	completed.emit(hacker_id)
	cleanup()
```

### 3. Machine Patrol
**Frequency**: Every 20 minutes  
**Duration**: 15 minutes or until all destroyed  
**Objective**: Destroy convoy of elite enemies

```gdscript
# server/events/MachinePatrolEvent.gd
class_name MachinePatrolEvent extends WorldEvent

var patrol_path: Array[Vector2]
var patrol_enemies: Array[Enemy] = []
var current_waypoint: int = 0

func activate():
	Net.client_show_event_announcement.rpc({
		"type": "machine_patrol",
		"message": "Elite machine patrol detected!",
		"position": patrol_path[0],
		"duration": 900.0
	})
	
	_spawn_patrol()

func _spawn_patrol():
	for i in range(5):  # 5 elite enemies
		var enemy = Enemy.new()
		enemy.net_id = Replication.generate_id()
		enemy.global_position = patrol_path[0] + Vector2(i * 40, 0)
		enemy.health = GameConstants.ENEMY_MAX_HEALTH * 2.0  # Tougher
		enemy.died.connect(_on_enemy_killed)
		ServerMain._world.add_child(enemy)
		patrol_enemies.append(enemy)
		
		# Spawn network event
		...

func _physics_process(delta):
	# Move patrol along path
	if patrol_enemies.is_empty():
		completed.emit(0)
		cleanup()
		return
	
	# Navigate to next waypoint
	...

func _on_enemy_killed(enemy_id: int):
	# Check if all dead
	if patrol_enemies.is_empty():
		completed.emit(0)
		cleanup()
```

## Event Scheduler

```gdscript
# ServerMain.gd
var _event_scheduler: EventScheduler

func _ready():
	_event_scheduler = EventScheduler.new()
	add_child(_event_scheduler)

# server/EventScheduler.gd
class_name EventScheduler extends Node

var active_events: Array[WorldEvent] = []
var next_event_times: Dictionary = {}  # event_type -> unix_time

const EVENT_INTERVALS = {
	"supply_drop": 600.0,      # 10 min
	"data_cache": 900.0,       # 15 min
	"machine_patrol": 1200.0   # 20 min
}

func _ready():
	# Initialize next event times
	var current_time = Time.get_unix_time_from_system()
	for event_type in EVENT_INTERVALS:
		next_event_times[event_type] = current_time + randf_range(60, 300)

func _process(_delta):
	_check_spawn_events()
	_tick_active_events()

func _check_spawn_events():
	var current_time = Time.get_unix_time_from_system()
	
	for event_type in next_event_times:
		if current_time >= next_event_times[event_type]:
			_spawn_event(event_type)
			next_event_times[event_type] = current_time + EVENT_INTERVALS[event_type]

func _spawn_event(event_type: String):
	var event: WorldEvent = null
	
	match event_type:
		"supply_drop":
			event = SupplyDropEvent.new()
			event.drop_position = _get_random_open_position()
		"data_cache":
			event = DataCacheEvent.new()
			event.terminal_position = _get_random_landmark_position()
		"machine_patrol":
			event = MachinePatrolEvent.new()
			event.patrol_path = _generate_patrol_path()
	
	if event:
		event.completed.connect(_on_event_completed)
		active_events.append(event)
		add_child(event)
		event.activate()

func _get_random_open_position() -> Vector2:
	# Find position away from structures
	for i in range(10):
		var pos = Vector2(randf_range(100, 900), randf_range(100, 500))
		if _is_position_clear(pos, 100):
			return pos
	return Vector2(500, 300)  # Fallback
```

## Client Announcement UI

```gdscript
# client/EventAnnouncement.gd
class_name EventAnnouncement extends PanelContainer

var event_type: String
var message: String
var world_position: Vector2
var duration: float
var time_remaining: float

func _ready():
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	# Icon
	var icon = TextureRect.new()
	icon.texture = _get_event_icon(event_type)
	icon.custom_minimum_size = Vector2(64, 64)
	vbox.add_child(icon)
	
	# Message
	var label = Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(label)
	
	# Timer
	var timer_label = Label.new()
	timer_label.name = "Timer"
	vbox.add_child(timer_label)
	
	# Navigate button
	var nav_btn = Button.new()
	nav_btn.text = "Mark on Map"
	nav_btn.pressed.connect(_on_mark_pressed)
	vbox.add_child(nav_btn)
	
	time_remaining = duration

func _process(delta):
	time_remaining -= delta
	
	var mins = int(time_remaining / 60)
	var secs = int(time_remaining) % 60
	get_node("Timer").text = "%d:%02d remaining" % [mins, secs]
	
	if time_remaining <= 0:
		queue_free()

func _on_mark_pressed():
	ClientMain._minimap.add_event_marker(world_position, event_type)

# ClientMain.gd
func _on_event_announcement(data: Dictionary):
	var announcement = EventAnnouncement.new()
	announcement.event_type = data.type
	announcement.message = data.message
	announcement.world_position = data.position
	announcement.duration = data.duration
	_hud.add_child(announcement)
```

## Minimap Event Markers

```gdscript
# client/Minimap.gd
var event_markers: Array[Dictionary] = []  # {pos, type, icon}

func add_event_marker(world_pos: Vector2, event_type: String):
	event_markers.append({
		"pos": world_pos,
		"type": event_type,
		"icon": _get_event_icon(event_type)
	})
	queue_redraw()

func _draw():
	# ... existing minimap code
	
	# Draw event markers
	for marker in event_markers:
		var map_pos = _world_to_map_pos(marker.pos)
		draw_texture_rect(marker.icon, Rect2(map_pos - Vector2(10, 10), Vector2(20, 20)), false)
		
		# Pulsing ring
		var pulse = sin(Time.get_ticks_msec() * 0.005) * 0.5 + 0.5
		draw_circle(map_pos, 15 + pulse * 10, Color(1, 1, 0, 0.3), false, 2.0)
```

## Implementation Steps

1. Create base WorldEvent class
2. Implement SupplyDropEvent
3. Implement DataCacheEvent  
4. Implement MachinePatrolEvent
5. Create EventScheduler
6. Build announcement UI
7. Add minimap markers

## Loot Tables

```gdscript
# shared/EventLootTables.gd
const SUPPLY_DROP_LOOT_TABLE = LootTable.new([
	{"item_id": "rare_weapon", "weight": 10, "min_qty": 1, "max_qty": 1},
	{"item_id": "advanced_ammo", "weight": 20, "min_qty": 50, "max_qty": 100},
	{"item_id": "rare_resource", "weight": 30, "min_qty": 10, "max_qty": 30},
	{"item_id": "medkit", "weight": 40, "min_qty": 3, "max_qty": 5}
])

const DATA_CACHE_REWARD = {
	"item_id": "classified_data",
	"value": 500,  # High currency value
	"xp": 1000
}
```

## Testing Checklist
- [ ] Events spawn on timer
- [ ] Announcements display correctly
- [ ] Minimap markers appear
- [ ] Supply drops spawn crates
- [ ] Data terminal hacking works
- [ ] Patrol enemies follow path
- [ ] Loot awards properly
- [ ] Multiple events can run simultaneously
