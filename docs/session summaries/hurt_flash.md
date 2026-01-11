# Hurt Flash Implementation - All Entities

## Overview

Added visual feedback (hurt flash) to all damageable entities except walls. When an entity takes damage, it flashes briefly to provide clear visual feedback.

## Implementation

### Entities with Hurt Flash

1. **Local Player** (your character)
   - Flashes RED when damaged
   - Applied in `_on_snapshot()` when health decreases

2. **Remote Players** (other players)
   - Flash RED when damaged
   - Applied in `_interpolate_entity()` when health decreases

3. **Enemies** (AI opponents)
   - Flash WHITE when damaged (contrast against dark red color)
   - Applied in `_interpolate_entity()` when health decreases
   - Also triggers on server in `take_damage()`

### Entities WITHOUT Hurt Flash

- **Walls**: Static structures, visual flash would be confusing/unnecessary

## Code Changes

### Enemy.gd
```gdscript
// Added hurt flash timer
var _hurt_flash_timer: float = 0.0

// Flash effect in _physics_process()
if _hurt_flash_timer > 0.0:
    _hurt_flash_timer -= delta
    var flash_intensity = _hurt_flash_timer / 0.2
    _sprite.modulate = Color.WHITE.lerp(Color.DARK_RED, 1.0 - flash_intensity)
else:
    _sprite.modulate = Color.DARK_RED

// Trigger on server damage
func take_damage(amount: float) -> bool:
    health -= amount
    _hurt_flash_timer = 0.2  // Server-side flash

// Trigger on client interpolation
func apply_replicated_state(state: Dictionary) -> void:
    var new_health = state.get("h", health)
    if new_health < health:
        _hurt_flash_timer = 0.2  // Client-side flash
```

### ClientMain.gd - _interpolate_entity()
```gdscript
// Check for health decrease during interpolation
if sb.has("h") and "health" in entity:
    var new_health = sb["h"]
    if entity is Player or entity is Enemy:
        if new_health < entity.health:
            entity._hurt_flash_timer = 0.2  // Trigger flash
    entity.health = new_health
```

### Player.gd (already existed)
```gdscript
// Flash RED on damage
if _hurt_flash_timer > 0.0:
    _sprite.modulate = Color.RED.lerp(_get_base_color(), 1.0 - flash_intensity)
```

## Flash Colors

| Entity Type | Flash Color | Base Color | Duration |
|-------------|-------------|------------|----------|
| Local Player | RED | BLACK | 0.2s |
| Remote Players | RED | ID-based color | 0.2s |
| Enemies | WHITE | DARK_RED | 0.2s |
| Walls | N/A | GRAY | N/A |

## Where Flashes Trigger

### Server-Side (Authoritative)
- `take_damage()` function sets timer
- Only matters for entities simulated on server
- Ensures server sees the flash even if client lags

### Client-Side (Visual)
1. **Local Player**: `_on_snapshot()` detects health drop
2. **Remote Players**: `_interpolate_entity()` detects health drop
3. **Enemies**: `_interpolate_entity()` detects health drop

## Benefits

- ✅ Clear visual feedback when taking damage
- ✅ Works for all entity types (players and enemies)
- ✅ Consistent 0.2 second duration
- ✅ Different colors for different entity types
- ✅ Works across network (server + client)
- ✅ No flash on walls (would be confusing)

## Performance

**Negligible impact**:
- Single timer per entity
- Simple lerp calculation in _process()/_physics_process()
- Only active for 0.2s after damage
- Most entities not flashing at any given time
