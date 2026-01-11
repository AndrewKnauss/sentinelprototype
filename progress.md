# Progress

## Completed

### Core Systems (Jan 2026)
- ✅ Client-server architecture (Godot 4.4 ENet)
- ✅ Client prediction + server reconciliation
- ✅ Entity interpolation (players, enemies, walls)
- ✅ ReplicationManager for entity registry
- ✅ Bootstrap launcher (--server / --client args)

### Entities
- ✅ Player (movement, shooting, building)
- ✅ Enemy (AI: chase/wander/separate, shooting)
- ✅ Bullet (client-predicted, client-collision)
- ✅ Wall (buildable, damageable, physics collision)

### Networking
- ✅ Input buffering + sequence numbers
- ✅ Snapshot transmission
- ✅ ACK system for reconciliation
- ✅ Spawn/despawn RPCs
- ✅ Client-side bullet prediction (zero-latency shooting)
- ✅ Client-side collision detection

### Polish
- ✅ Camera following local player (smooth)
- ✅ Fullscreen scaling (1920x1080)
- ✅ Test session launcher (1 server + 3 clients, quadrant layout)

## In Progress
- None

## Next Up
- World events (timed loot spawns)
- Inventory system
- Resource gathering
- Hot loot mechanics
- PvP zones with lawfulness gradient
- Bounty system
