# Hot Loot System

## Overview
Stolen/looted items become "hot" - increasing AI aggro, visible on map, and preventing storage. Deters low-level griefing.

## Core Mechanics

### Hot State Tracking
```gdscript
# shared/ItemData.gd - Add fields
var is_hot: bool = false
var hot_timer: float = 0.0
const HOT_DURATION = 300.0  # 5 minutes

# entities/Inventory.gd
func mark_item_hot(slot_idx: int):
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	
	slots[slot_idx].is_hot = true
	slots[slot_idx].hot_timer = ItemData.HOT_DURATION

func tick_hot_items(delta: float):
	for slot in slots:
		if slot.is_hot:
			slot.hot_timer -= delta
			if slot.hot_timer <= 0:
				slot.is_hot = false
```

### Trigger Conditions
```gdscript
# ServerMain.gd
func _on_player_killed(victim: Player, killer: Player):
	# Mark all victim's loot as hot when dropped
	var dropped_items = victim.inventory.get_all_items()
	
	for item in dropped_items:
		_spawn_item_drop(victim.global_position, item.id, item.qty, true)  # hot=true

func _spawn_item_drop(pos: Vector2, item_id: String, qty: int, is_hot: bool = false):
	var drop = ItemDrop.new()
	# ... existing setup
	drop.is_hot = is_hot
	drop.hot_timer = ItemData.HOT_DURATION if is_hot else 0.0
	
	# Visual indicator
	if is_hot:
		drop.set_hot_visual()

func _on_pickup_item(player: Player, drop: ItemDrop):
	var slot_idx = player.inventory.add_item(drop.item_id, drop.quantity)
	
	# Transfer hot status
	if drop.is_hot and slot_idx >= 0:
		player.inventory.mark_item_hot(slot_idx)
```

## AI Aggro Modifier

```gdscript
# entities/Enemy.gd
const AGGRO_RANGE_BASE = 600.0
const AGGRO_RANGE_HOT_MULTIPLIER = 2.0

func _get_aggro_range() -> float:
	var max_range = AGGRO_RANGE_BASE
	
	# Check all players for hot items
	for entity in Replication.get_all_entities():
		if entity is Player:
			if entity.inventory.has_hot_items():
				var dist = global_position.distance_to(entity.global_position)
				# Hot items extend aggro range
				if dist < (AGGRO_RANGE_BASE * AGGRO_RANGE_HOT_MULTIPLIER):
					max_range = AGGRO_RANGE_BASE * AGGRO_RANGE_HOT_MULTIPLIER
	
	return max_range

func _find_target() -> Player:
	# Prioritize players with hot loot
	var hot_players: Array[Player] = []
	var normal_players: Array[Player] = []
	
	for entity in Replication.get_all_entities():
		if entity is Player:
			var dist = global_position.distance_to(entity.global_position)
			if dist < _get_aggro_range():
				if entity.inventory.has_hot_items():
					hot_players.append(entity)
				else:
					normal_players.append(entity)
	
	# Prefer hot targets
	if not hot_players.is_empty():
		return hot_players[randi() % hot_players.size()]
	elif not normal_players.is_empty():
		return normal_players[randi() % normal_players.size()]
	
	return null
```

## Storage Prevention

```gdscript
# entities/StorageBox.gd (new building type)
class_name StorageBox extends NetworkedEntity

var contents: Array[Dictionary] = []  # Inventory slots

func try_deposit(player: Player, slot_idx: int) -> bool:
	var item = player.inventory.slots[slot_idx]
	
	# Reject hot items
	if item.is_hot:
		return false  # Can't store hot loot
	
	# Transfer to storage
	contents.append(item)
	player.inventory.remove_slot(slot_idx)
	return true
```

## Map Visibility

```gdscript
# client/HotLootMarker.gd
class_name HotLootMarker extends Control

var world_pos: Vector2
var hot_player_id: int

func _process(_delta):
	# Update screen position
	var camera = get_viewport().get_camera_2d()
	if camera:
		var screen_pos = camera.get_screen_center_position() + (world_pos - camera.global_position)
		position = screen_pos

# ClientMain.gd - Update HUD
func _update_hot_loot_markers():
	# Clear old markers
	for marker in _hot_markers:
		marker.queue_free()
	_hot_markers.clear()
	
	# Create markers for all players with hot items
	for entity in Replication.get_all_entities():
		if entity is Player and entity.inventory.has_hot_items():
			var marker = HotLootMarker.new()
			marker.world_pos = entity.global_position
			marker.hot_player_id = entity.net_id
			_hud.add_child(marker)
			_hot_markers.append(marker)
```

## Visual Indicators

```gdscript
# entities/ItemDrop.gd
func set_hot_visual():
	# Red glow particle effect
	var particles = GPUParticles2D.new()
	particles.amount = 8
	particles.lifetime = 0.5
	particles.process_material = _create_hot_particle_material()
	add_child(particles)
	
	# Red outline
	_sprite.modulate = Color.RED

func _create_hot_particle_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 10.0
	mat.direction = Vector3(0, -1, 0)
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 40.0
	mat.gravity = Vector3(0, -50, 0)
	mat.color = Color.RED
	return mat

# UI/InventorySlot.gd
func _draw():
	# Draw red border if hot
	if item_data and item_data.is_hot:
		draw_rect(Rect2(Vector2.ZERO, size), Color.RED, false, 2.0)
		
		# Show timer
		var time_left = int(item_data.hot_timer)
		var label = "%d:%02d" % [time_left / 60, time_left % 60]
		draw_string(font, Vector2(4, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.RED)
```

## Decay Mechanics

```gdscript
# ServerMain.gd
func _physics_process(delta):
	# ... existing code
	
	# Tick hot timers on all players
	for peer_id in _players:
		var player = _players[peer_id]
		player.inventory.tick_hot_items(delta)

# Alternative: Items cool down faster if dropped
func _spawn_item_drop(pos, item_id, qty, is_hot):
	# ... existing code
	
	if is_hot:
		drop.hot_decay_rate = 2.0  # Cools 2x faster when dropped
```

## Implementation Steps

1. Add `is_hot` + `hot_timer` to ItemData
2. Mark items hot on player death
3. Implement aggro range modifier in Enemy.gd
4. Add storage prevention to containers
5. Create map marker UI
6. Add visual indicators (particles, outlines)
7. Implement decay timer system

## Balance Tuning

```gdscript
# shared/HotLootConfig.gd
const HOT_DURATION = 300.0         # 5 minutes base
const AGGRO_MULTIPLIER = 2.0       # 2x enemy range
const DECAY_RATE_DROPPED = 2.0     # Cool faster if dropped
const DECAY_RATE_BANKED = 0.0      # Can't store at all (alternative: very slow)
const MAP_MARKER_RANGE = 500.0     # Show marker within this range
```

## Edge Cases

**Problem**: Player logs out with hot items  
**Solution**: Hot timer pauses when offline, resumes on login

**Problem**: Player dies with hot items  
**Solution**: Items stay hot when re-dropped (chain effect)

**Problem**: Dropping hot items to bypass storage  
**Solution**: Items cool faster but not instantly (2x rate)

## Testing Checklist
- [ ] Items marked hot on PvP kill
- [ ] AI aggro range increases near hot players
- [ ] Storage rejects hot items
- [ ] Map markers show hot players
- [ ] Visual effects display correctly
- [ ] Timer counts down properly
- [ ] Items cool after duration expires
