# Client-Side Bullet Collision Fix

## Problem
After implementing client-side prediction for bullets, bullets were passing through all entities (players, enemies, walls) without any collision detection.

## Root Cause
- Original collision detection was in `ServerMain._process_bullets()`
- When bullets became client-predicted, they no longer ran through server collision logic
- Predicted bullets on client had no collision detection at all

## Solution: Move Collision to Bullet Entity

### Changes Made:

1. **Bullet.gd** - Added `_check_collision()` method:
   - Runs on both client AND server
   - Checks collisions before moving each frame
   - Uses raycast for wall collision (physics layers)
   - Uses distance checks for player/enemy collision
   - Returns `true` if hit something (triggers `queue_free()`)

2. **Bullet.gd** - Separate hit handlers for each entity type:
   - `_on_hit_wall()` - Damages wall, despawns bullet
   - `_on_hit_player()` - Damages player, respawns if killed
   - `_on_hit_enemy()` - Damages enemy, respawns if killed
   - Server applies damage and sends despawn RPC to clients
   - Client just despawns visually (damage is server-authoritative)

3. **ServerMain.gd** - Simplified bullet management:
   - Removed duplicate collision code from `_process_bullets()`
   - Renamed to `_cleanup_bullets()` - just removes invalid bullets
   - Collision detection now happens in Bullet entity itself

### How It Works:

**Client-Side (Predicted Bullet):**
1. Player shoots → bullet spawns instantly
2. Every frame: `Bullet._check_collision()` runs
3. If hit → bullet despawns locally (instant visual feedback)
4. Server validates hits separately (authoritative)

**Server-Side (Authoritative Bullet):**
1. Receives input → spawns bullet
2. Every frame: `Bullet._check_collision()` runs
3. If hit → applies damage, sends despawn RPC to all clients
4. Clients receive despawn and remove their visual copy

**Other Player's Bullet (on your client):**
1. Receive spawn RPC from server
2. Spawn bullet locally
3. Every frame: `Bullet._check_collision()` runs (visual only)
4. If hit → despawns locally
5. Server's authoritative copy handles actual damage

### Benefits:
- ✅ Bullets collide properly on all clients
- ✅ Instant visual feedback for your own bullets
- ✅ Server remains authoritative for damage
- ✅ Collision logic centralized in Bullet entity
- ✅ No duplicate code between client and server

### Architecture:
```
Bullet Entity (runs everywhere):
├─ _physics_process()
│  ├─ _check_collision() → returns true if hit
│  │  ├─ Raycast for walls
│  │  ├─ Distance check for players
│  │  └─ Distance check for enemies
│  ├─ if hit: queue_free()
│  └─ else: move forward
│
└─ Hit Handlers:
   ├─ _on_hit_wall() → damage + despawn RPC
   ├─ _on_hit_player() → damage + respawn + despawn RPC
   └─ _on_hit_enemy() → damage + despawn RPC
```

### Notes:
- Client collision is "optimistic" - visual feedback happens instantly
- Server collision is authoritative - determines actual game state
- If client and server disagree, server wins (as it should)
- Works well because bullets are fast and disposable
