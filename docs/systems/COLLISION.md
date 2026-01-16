# COLLISION.md - Collision & Physics Layer Design

## Overview

Godot's collision system uses **32 physics layers** (bit flags) to control what objects can interact. This document defines our layer structure for movement collision, line-of-sight raycasting, and sound propagation.

**Critical Principle**: Separation of concerns
- **Collision Layers** = "I am on these layers"
- **Collision Masks** = "I collide with these layers"
- **Raycasting** uses masks independently of movement collision

---

## Current Implementation (Phase 1)

### Layer Assignments

| Layer | Name | Purpose | Examples |
|-------|------|---------|----------|
| 1 | `STATIC` | Immovable structures | Walls, foundations, terrain obstacles |
| 2 | `PLAYER` | Player characters | Local/remote players |
| 3 | `ENEMY` | AI hostiles | Scouts, tanks, snipers, swarms |
| 4 | `PROJECTILE` | Bullets/explosives | All weapon projectiles |
| 5 | `ITEMS` | Loot drops | ItemDrop entities on ground |
| 6 | `INTERACTION` | Pickup/use range | Tool cupboards, workbenches, doors |

### Entity Collision Setup

```gdscript
# Wall.gd (StaticBody2D)
func _ready():
    collision_layer = 1   # I am STATIC
    collision_mask = 0    # I don't move, no checks needed

# Player.gd (NetworkedEntity with CharacterBody2D child)
func _ready():
    # Create collision body as child
    _collision_body = CharacterBody2D.new()
    _collision_body.collision_layer = 2      # Layer 2 = PLAYER
    _collision_body.collision_mask = 1 | 2   # Collide with STATIC + PLAYER
    add_child(_collision_body)
    
    # Add collision shape
    var shape = CollisionShape2D.new()
    var circle = CircleShape2D.new()
    circle.radius = 8.0
    shape.shape = circle
    _collision_body.add_child(shape)
    # Note: Don't collide with ENEMY (allows phasing through)

# Enemy.gd (NetworkedEntity with CharacterBody2D child)
func _ready():
    # Create collision body as child
    _collision_body = CharacterBody2D.new()
    _collision_body.collision_layer = 4      # Layer 3 = ENEMY (bit value 4)
    _collision_body.collision_mask = 1 | 4   # Collide with STATIC + ENEMY
    add_child(_collision_body)
    
    var shape = CollisionShape2D.new()
    var circle = CircleShape2D.new()
    circle.radius = 10.0
    shape.shape = circle
    _collision_body.add_child(shape)
    # Note: Don't collide with PLAYER (allows phasing through)

# Movement with collision - CORRECT PATTERN
func apply_input(mv: Vector2, dt: float):
    velocity = mv * MOVE_SPEED
    var motion = velocity * dt
    
    # Test collision using child body
    _collision_body.velocity = velocity
    var collision = _collision_body.move_and_collide(motion)
    
    if collision:
        # Slide along walls
        var slide_velocity = velocity.slide(collision.get_normal())
        var slide_motion = slide_velocity * dt
        _collision_body.move_and_collide(slide_motion)
        
        # Apply child's LOCAL movement to parent's GLOBAL position
        global_position += _collision_body.position
        # Reset child to (0,0) - CRITICAL to prevent feedback loop
        _collision_body.position = Vector2.ZERO
    else:
        # No collision - apply full movement
        global_position += motion
        # Child stays centered
        _collision_body.position = Vector2.ZERO

# Bullet.gd (Area2D - uses raycasting, not collision layers)
func _check_collision():
    # Raycasts to detect hits (see Bullet.gd implementation)
    pass
```

**Why Players/Enemies Don't Collide:**
- Prevents body-blocking griefing
- Allows smooth multi-enemy swarms
- Combat is ranged, not melee
- Still blocks each from walking through walls

**Architecture Note:**
- **Component-based networking** (refactored in Session #5)
- `NetworkedEntity` is a **RefCounted component**, not a base class
- Entities extend their proper physics body types:
  - `Player` extends `CharacterBody2D`
  - `Enemy` extends `CharacterBody2D`
  - `Wall` extends `StaticBody2D`
  - `Bullet` extends `Node2D` (uses raycasting)
- Each entity has `net_entity: NetworkedEntity` component for replication
- **Movement pattern**:
  ```gdscript
  # Clean and simple - native Godot physics
  velocity = movement * speed
  move_and_slide()  # That's it!
  ```
- **No position syncing** - entities ARE their physics bodies
- **Why this works**: 
  - Parent entity owns physics behavior completely
  - NetworkedEntity component only handles replication
  - No parent-child position feedback loops
  - Godot-idiomatic (composition over inheritance)

**Why not extend CharacterBody2D directly in base class?**
- Different entities need different physics body types
- Component pattern keeps system flexible and clean
- Easy to add non-networked entities

---

## Phase-Through Flags (Optional)

For admin/spectator modes or special abilities:

```gdscript
# Player.gd
var can_phase_through_walls: bool = false
var can_phase_through_players: bool = false

func _update_collision_mask():
    var mask = 0
    if not can_phase_through_walls:
        mask |= 1  # STATIC
    if not can_phase_through_players:
        mask |= 2  # PLAYER
    _collision_body.collision_mask = mask
```

**Use Cases:**
- Admin noclip mode (debug)
- Spectator after death
- Future "ghost" status effect

---

## Future Systems Integration

### Fog of War / Line-of-Sight (Phase 2)

**Requirements:**
- Walls block player vision (can't see enemies behind walls)
- Raycasts from player to enemy/loot
- Client-side visibility culling

**Implementation:**

```gdscript
# ClientMain.gd - Visibility check
func _is_visible_to_local_player(target_pos: Vector2) -> bool:
    var player_pos = _local_player.position
    var space_state = get_world_2d().direct_space_state
    
    var query = PhysicsRayQueryParameters2D.create(player_pos, target_pos)
    query.collision_mask = 1  # Only check STATIC layer (walls)
    query.exclude = [_local_player]
    
    var result = space_state.intersect_ray(query)
    return result.is_empty()  # True if no wall blocking

# Apply to rendering
func _process(delta):
    for enemy in _enemies.values():
        enemy.visible = _is_visible_to_local_player(enemy.position)
    for item in _items.values():
        item.visible = _is_visible_to_local_player(item.position)
```

**Layer 7 - FOG_BLOCKER** (future):
- Separate from physical collision
- Allows one-way vision (mirrors, windows)
- Smoke grenades spawn temporary fog entities

**Fog of War Edge Cases:**
- Minimap shows last-known positions (grayed out)
- Muzzle flashes reveal position briefly
- Sound indicators (gunfire) show direction without full vision

---

### Sound/Proximity System (Phase 3)

**Requirements:**
- Gunfire alerts nearby enemies (radius-based)
- Walls muffle sound (reduce alert radius)
- Sprinting/dashing creates noise
- Enemy "hearing" independent of vision

**Implementation:**

```gdscript
# SoundPropagation.gd (autoload singleton)
func emit_sound(origin: Vector2, loudness: float, category: String):
    # category: "gunshot", "footstep", "explosion", "dash"
    
    var base_radius = _get_base_radius(category)  # gunshot = 800, footstep = 100
    
    # Raycast to each enemy to check wall muffling
    for enemy in ServerMain._enemies.values():
        var distance = origin.distance_to(enemy.position)
        if distance > base_radius:
            continue
        
        var effective_radius = base_radius
        
        # Reduce radius for each wall between source and enemy
        var walls_blocking = _count_walls_between(origin, enemy.position)
        effective_radius *= pow(0.6, walls_blocking)  # -40% per wall
        
        if distance <= effective_radius:
            enemy.on_sound_heard(origin, loudness, category)

func _count_walls_between(from: Vector2, to: Vector2) -> int:
    var space_state = ServerMain.get_world_2d().direct_space_state
    var count = 0
    var check_pos = from
    
    while check_pos.distance_to(to) > 10:
        var query = PhysicsRayQueryParameters2D.create(check_pos, to)
        query.collision_mask = 1  # STATIC only
        var result = space_state.intersect_ray(query)
        
        if result.is_empty():
            break
        
        count += 1
        check_pos = result.position + (to - check_pos).normalized() * 10
        
        if count > 10:  # Safety limit
            break
    
    return count
```

**Enemy Response:**

```gdscript
# Enemy.gd
func on_sound_heard(source_pos: Vector2, loudness: float, category: String):
    # Gunshots = investigate
    # Explosions = flee briefly
    # Footsteps = alert if already searching
    
    match category:
        "gunshot", "explosion":
            _investigate_position = source_pos
            _state = INVESTIGATE
            _state_timer = 5.0
        "footstep", "dash":
            if _state == INVESTIGATE or _state == CHASE:
                _investigate_position = source_pos
```

**Sound Sources:**

| Action | Base Radius | Notes |
|--------|-------------|-------|
| Pistol shot | 600 | |
| Rifle shot | 800 | |
| Shotgun blast | 700 | |
| Sniper shot | 1000 | Loudest weapon |
| Explosion | 1200 | Grenades, barrel explosions |
| Sprint footsteps | 150 | Continuous while moving |
| Dash | 200 | Single burst |
| Walking | 50 | Minimal alert |

---

### Interaction Raycasting (Phase 4)

**Requirements:**
- E-key pickup (raycast to nearest item)
- Door usage (raycast to door hitbox)
- Workbench interaction
- Tool cupboard authorization

**Implementation:**

```gdscript
# Player.gd - Interaction check
func _check_interaction() -> Node2D:
    var space_state = get_world_2d().direct_space_state
    var forward = Vector2.from_angle(_aim_angle) * 100  # 100px reach
    
    var query = PhysicsRayQueryParameters2D.create(position, position + forward)
    query.collision_mask = 6  # Layer 6 = INTERACTION
    var result = space_state.intersect_ray(query)
    
    if not result.is_empty():
        return result.collider
    return null

# ClientMain.gd - E-key handling
func _unhandled_input(event):
    if event.is_action_pressed("ui_interact"):  # E key
        var target = _local_player._check_interaction()
        if target:
            if target is ItemDrop:
                Net.server_pickup_item.rpc_id(1, target.net_id)
            elif target is Door:
                Net.server_toggle_door.rpc_id(1, target.net_id)
            elif target is ToolCupboard:
                # Open authorization UI
                _show_cupboard_ui(target)
```

**Layer 6 Usage:**
- Items: Area2D with small radius (32px)
- Doors: StaticBody2D on layer 1 + 6 (physical + interactable)
- Workbenches: Area2D trigger zone

---

## Collision Performance Optimization

### Spatial Partitioning (Future)

When entity count exceeds 200, use chunk-based collision:

```gdscript
# CollisionGrid.gd (autoload)
const CHUNK_SIZE = 512  # pixels
var _chunks: Dictionary = {}  # Vector2i -> Array[Entity]

func get_nearby_entities(pos: Vector2, radius: float) -> Array:
    var chunk_pos = Vector2i(pos / CHUNK_SIZE)
    var nearby = []
    
    for x in range(-1, 2):
        for y in range(-1, 2):
            var check = chunk_pos + Vector2i(x, y)
            if check in _chunks:
                nearby.append_array(_chunks[check])
    
    return nearby.filter(func(e): return pos.distance_to(e.position) <= radius)
```

**Benefits:**
- O(n) → O(log n) for proximity checks
- Scales to 1000+ entities
- Critical for sound propagation (avoid checking every enemy)

---

## Debug Visualization

**F4 key toggles collision debug overlay:**

```gdscript
# ClientMain.gd
func _input(event):
    if event.is_action_pressed("debug_collision"):
        get_tree().debug_collisions_hint = !get_tree().debug_collisions_hint

# Shows:
# - Blue boxes: collision shapes
# - Red lines: raycasts
# - Yellow circles: sound propagation radius
```

---

## Known Issues & Solutions

### Issue: Entities teleporting or moving in circles (FIXED in Session #5)
**Cause**: Old architecture used parent-child pattern with position syncing  
**Solution**: Complete refactor to component pattern
- Changed `NetworkedEntity` from Node2D base class to RefCounted component
- Entities now extend their physics bodies directly (CharacterBody2D, StaticBody2D)
- Movement uses native `move_and_slide()` with no position syncing
- Eliminated parent-child feedback loops entirely

**Old broken pattern (Session #5 initial attempt):**
```gdscript
# WRONG - creates feedback loop
var collision = _collision_body.move_and_collide(motion)
global_position = _collision_body.global_position  # BAD!
# Next frame: child offset from parent → spiral/teleport
```

**Current clean pattern:**
```gdscript
# CORRECT - entity IS the physics body
velocity = movement * speed
move_and_slide()  # Simple, clean, no syncing needed
```

### Issue: Players getting stuck in walls after lag spike
**Cause**: Position reconciliation puts player inside wall hitbox  
**Solution**: Server checks `test_move()` before accepting position
```gdscript
# ServerMain.gd
func _apply_input(player, input):
    var new_velocity = input.movement * MOVE_SPEED
    if not player._collision_body.test_move(player._collision_body.transform, new_velocity * delta):
        # Valid move, proceed
        pass
    else:
        # Collision detected, reject movement
        pass
```

### Issue: Collision body position desyncs from parent
**Cause**: Forgetting to sync positions  
**Solution**: Always sync after movement
```gdscript
# After every move_and_collide
global_position = _collision_body.global_position
```

### Issue: Enemies clustering on same side of wall
**Cause**: All enemies pathfind to same nearest point  
**Solution**: Add random offset to pathfinding target
```gdscript
# Enemy.gd
func _calculate_path_to(target_pos: Vector2):
    var offset = Vector2(randf_range(-50, 50), randf_range(-50, 50))
    return _navmesh.get_path(position, target_pos + offset)
```

---

## Testing Checklist

- [x] Players blocked by walls
- [x] Enemies blocked by walls  
- [x] Bullets hit walls and stop (unchanged)
- [x] Players can walk through enemies
- [x] Enemies can walk through players
- [ ] Phase-through flag works (admin mode) - Not yet implemented
- [ ] No stuck-in-wall scenarios after lag

---

## Migration Path

### Phase 1 (Current): Basic Collision ✓
- Walls block movement
- Bullets hit walls
- No player/enemy collision
- Wall sliding behavior

### Phase 2 (Week 3): Fog of War
- Raycast visibility checks
- Client-side entity culling
- Minimap last-known positions

### Phase 3 (Week 4): Sound System
- Gunshot alerts
- Wall muffling
- Enemy investigation AI

### Phase 4 (Week 5): Advanced Interaction
- E-key raycasting
- Door/workbench interaction
- Spatial query optimization

---

## Constants Reference

```gdscript
# GameConstants.gd additions
const INTERACTION_RANGE: float = 100.0
const SOUND_WALL_DAMPENING: float = 0.6  # -40% per wall

# Collision layers (bit flags)
const LAYER_STATIC: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 4
const LAYER_PROJECTILE: int = 8
const LAYER_ITEMS: int = 16
const LAYER_INTERACTION: int = 32
const LAYER_FOG_BLOCKER: int = 64  # Future

# Sound radii
const SOUND_PISTOL: float = 600.0
const SOUND_RIFLE: float = 800.0
const SOUND_SHOTGUN: float = 700.0
const SOUND_SNIPER: float = 1000.0
const SOUND_EXPLOSION: float = 1200.0
const SOUND_SPRINT: float = 150.0
const SOUND_DASH: float = 200.0
const SOUND_WALK: float = 50.0
```

---

## Summary

**Current State**: Phase 1 complete - Walls block movement with slide behavior  
**Architecture**: CharacterBody2D child nodes for Player/Enemy collision  
**Future Ready**: Designed for FOG, sound, interaction  
**Performance**: Scales to 1000+ entities with spatial partitioning  
**Flexibility**: Phase-through flags for special modes (not yet implemented)
