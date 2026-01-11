# Wall Optimization - Static Entity Handling

## Problem

Walls were being treated like dynamic entities (players, enemies) and interpolated every frame, even though they never move after being placed. This was a performance waste.

## Solution

Treat walls as **static entities** with special handling:

### Before (Wasteful)
```gdscript
// Every frame, for every wall:
for net_id in _snap_buffers:
    var entity = Replication.get_entity(net_id)
    if entity is Wall:
        // Interpolate position (which never changes!)
        _interpolate_entity(entity, render_tick)
```

### After (Optimized)
```gdscript
// In snapshot handler:
if entity is Wall:
    // Only update health, skip interpolation
    entity.health = state["h"]
    continue  // Don't add to buffer

// In interpolation loop:
if entity is Wall:
    continue  // Skip entirely
```

## Changes Made

### ClientMain.gd
1. **`_on_snapshot()`**: Walls get health-only updates, skip interpolation buffer
2. **`_interpolate_all_entities()`**: Skip walls in interpolation loop
3. **Documentation**: Updated comments to reflect wall handling

### Architecture.md
1. Updated entity handling table (Walls: Static, 0ms latency)
2. Added "Wall Optimization Strategy" section
3. Updated "Static State" category
4. Performance notes added

### CLAUDE.md
1. Updated entity types description
2. Added wall optimization code pattern
3. Updated recent changes section

## Performance Impact

**Before**: N walls = N entities in interpolation loop every frame
**After**: N walls = 0 entities in interpolation loop

**Estimated savings**:
- 30-50% fewer entities interpolated per frame (depends on wall count)
- Zero CPU cycles spent lerping static positions
- Reduced memory pressure from interpolation buffers

**Example**: With 20 walls built:
- Before: 20 interpolations/frame (wasted)
- After: 0 interpolations/frame

## Why This Matters

1. **Scalability**: More walls = worse performance before, no impact after
2. **Base Building**: Game encourages building, this removes the penalty
3. **Future-Proof**: Sets pattern for other static entities (resource nodes, etc.)

## Entity Categories Now

| Type | Position | Health | Strategy |
|------|----------|--------|----------|
| Local Player | Predicted | Snapshot | Prediction + reconciliation |
| Remote Players | Interpolated | Interpolated | 2-tick delay interpolation |
| Enemies | Interpolated | Interpolated | 2-tick delay interpolation |
| **Walls** | **Static** | **Snapshot** | **Set once + health updates** |
| Bullets | Predicted | N/A | Pure client prediction |

## Code Locations

- `scripts/client/ClientMain.gd`: Lines 169-197, 322-330
- `docs/Architecture.md`: Entity table, Static State section
- `CLAUDE.md`: Entity types, Wall optimization pattern
