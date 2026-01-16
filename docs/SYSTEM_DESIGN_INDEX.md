# System Design Documentation - Master Index

## Purpose
These documents define major gameplay systems with implementation details, API usage, and integration points. Each is self-contained for independent development.

## Core Documentation

### [Architecture](ARCHITECTURE.md)
**Priority**: CRITICAL (read this first)  
**Complexity**: Comprehensive

Complete technical architecture documentation covering:
- Component-based networking pattern
- Entity types and physics bodies
- Client-side prediction and reconciliation
- Server-authoritative simulation
- Replication system
- Collision layers and movement
- Persistence system
- Network protocol
- File structure

**This is the definitive reference for how the game works.**

---

## Core Systems

### 1. [Loot System](systems/LOOT_SYSTEM.md)
**Dependencies**: None  
**Priority**: High (foundation for progression)  
**Complexity**: Medium

Item drops, inventory, pickup interaction, drop-on-death.

**Key Features**:
- ItemDrop entity (interpolated)
- Inventory component (20 slots)
- Loot tables (weighted random)
- E-key interaction
- Network sync

**Risks**: Item duplication on lag (server validates all pickups)

---

### 2. [Hot Loot System](systems/HOT_LOOT_SYSTEM.md)
**Dependencies**: Loot System  
**Priority**: Medium (anti-griefing)  
**Complexity**: Medium

Stolen items become "hot" - AI aggro, map visibility, storage prevention.

**Key Features**:
- 5-minute hot timer
- 2x AI aggro range
- Storage blocking
- Map markers
- Visual indicators (particles, red glow)

**Risks**: Exploit via dropping hot items (2x cooldown decay when dropped)

---

### 3. [Bounty System](systems/BOUNTY_SYSTEM.md)
**Dependencies**: Player levels, Currency  
**Priority**: Medium (anti-griefing)  
**Complexity**: Medium

Auto-bounties for level-diff kills, escalating rewards, map markers.

**Key Features**:
- Level difference tracking (5+ = griefing)
- Anti-farming cooldown (1 hour)
- Escalating values (1.5x per kill)
- Decay over time (30 min)
- Map markers + notifications

**Risks**: Bounty farming between friends (cooldown prevents)

---

### 4. [World Events](systems/WORLD_EVENTS.md)
**Dependencies**: Loot System  
**Priority**: High (core loop driver)  
**Complexity**: High

Timed high-value events to contest: Supply drops, data caches, machine patrols.

**Key Features**:
- EventScheduler (timer-based spawns)
- 3 event types (Supply Drop, Data Cache, Patrol)
- Announcement UI
- Minimap markers
- High-tier loot tables

**Risks**: Multiple overlapping events (limit to 2 concurrent)

---

### 5. [Lawfulness Zones](systems/LAWFULNESS_ZONES.md)
**Dependencies**: Reputation System  
**Priority**: Low (requires large map)  
**Complexity**: High

Map zones with PvP consequences: Safe → Neutral → Lawless.

**Key Features**:
- Zone definitions (Rect2 bounds)
- PvP blocking (Safe zones)
- Reputation penalties (Neutral)
- Loot scaling by zone
- Visual overlays
- Entry restrictions (hostile banned from Safe)

**Risks**: Current map too small - implement after world expansion

---

### 6. [Collision System](systems/COLLISION.md)
**Dependencies**: None  
**Priority**: CRITICAL (foundation for movement/FOG/sound)  
**Complexity**: Low (Phase 1), High (Future phases)

Collision layers for movement blocking, line-of-sight, and sound propagation.

**Key Features (Phase 1 - Implemented)**:
- Wall collision blocking (Layer 1 = STATIC)
- Player/Enemy movement with wall sliding
- Phase-through behavior (players/enemies don't collide)
- CharacterBody2D collision detection

**Future Phases**:
- Phase 2: Fog of War (raycast visibility, client culling)
- Phase 3: Sound System (gunshot alerts, wall muffling)
- Phase 4: Interaction (E-key raycasting, doors/workbenches)

**Risks**: Players getting stuck in walls after lag (server validates with test_move)

---

### 7. [Persistence](systems/PERSISTENCE.md)
**Dependencies**: None  
**Priority**: CRITICAL (required before other systems)  
**Complexity**: High

Database-backed saves for players, inventory, structures.

**Key Features**:
- SQLite database
- Player data (position, stats, inventory)
- Structure persistence (walls, etc)
- Autosave (5 min intervals)
- Graceful shutdown

**Risks**: Database corruption on crash (use WAL mode)

---

## Implementation Order

### Phase 1: Foundation (Week 1-2) ✓
1. **Persistence** - COMPLETE (JSON backend, autosave, username system)
2. **Collision System (Phase 1)** - COMPLETE (walls block movement)
3. **Loot System** - Next up

### Phase 2: Anti-Griefing (Week 3-4)
4. **Hot Loot** - Requires loot system
5. **Bounty System** - Requires levels/XP (add simple XP first)

### Phase 3: Content (Week 5-6)
6. **World Events** - Requires loot system
7. **Lawfulness Zones** - DEFER until map expansion
8. **Collision System (Phase 2-4)** - FOG, sound, interaction (after base building)

---

## Current Architecture Compatibility

All systems designed to integrate with existing:
- **ServerMain.gd** - Authoritative simulation
- **ClientMain.gd** - Prediction + interpolation
- **NetworkedEntity** - Base replication
- **Net.gd** - RPC transport

No major refactoring required.

---

## Missing Prerequisites

Before implementing these systems, add:

### Player Levels + XP
```gdscript
# entities/Player.gd additions
var level: int = 1
var xp: int = 0

func add_xp(amount: int):
	xp += amount
	while xp >= _xp_for_next_level():
		level += 1
		xp -= _xp_for_next_level()

func _xp_for_next_level() -> int:
	return 100 * level  # Simple formula
```

### Currency System
```gdscript
# entities/Player.gd additions
var currency: int = 0

func add_currency(amount: int):
	currency += amount
```

### Reputation System
```gdscript
# entities/Player.gd additions
var reputation: float = 0.0  # -1000 to +1000
```

---

## Testing Approach

Each system should be tested in isolation:

1. Create test scene with minimal setup
2. Spawn test entities
3. Verify network sync
4. Check edge cases
5. Load test (100+ entities)

---

## Performance Considerations

**Network Bandwidth**:
- Hot loot: +4 bytes per item (is_hot bool + timer float)
- Bounties: Broadcast on change only (not every tick)
- World events: Announcement is one-time RPC

**Database**:
- Autosave batches all players (not real-time)
- Structure loads happen once at server start
- Use prepared statements for repeated queries

---

## Known Issues & Solutions

**Issue**: Hot loot timer desync between server/client  
**Solution**: Server is authoritative, client displays only

**Issue**: Bounty duplication if player reconnects  
**Solution**: Database stores bounties, load on connect

**Issue**: Event markers clutter minimap  
**Solution**: Limit to 3 concurrent events max

**Issue**: Zone transitions feel jarring  
**Solution**: Add 2-second grace period before penalties apply
