# Bullet Interpolation Fix

## Problem
Bullets were being interpolated alongside other entities (players, enemies, walls), causing them to lag behind the player's movement. This created a disconnect between where the player was aiming and where bullets appeared.

## Root Cause
- Bullets were treated the same as other networked entities
- Server would spawn bullets and send spawn events to clients
- Clients would wait for the spawn event, then interpolate bullet positions
- This created ~2+ tick delay (interpolation delay) before bullets appeared

## Solution: Client-Side Prediction for Bullets

### Changes Made:

1. **ClientMain.gd** - Client now spawns bullets immediately:
   - When local player shoots, client spawns a "predicted" bullet instantly
   - Bullet gets temporary `net_id = -1` and `authority = player_id`
   - This gives instant visual feedback with zero latency

2. **ClientMain.gd** - Skip bullet interpolation:
   - `_interpolate_all_entities()` now skips bullets
   - `_on_snapshot()` doesn't add bullets to interpolation buffers
   - Bullets move purely based on their local physics simulation

3. **Net.gd** - Skip server bullet spawns for local player:
   - When server sends bullet spawn RPC, check if `owner_id == local_player_id`
   - If yes, skip spawning (we already predicted it)
   - If no, spawn it (it's from another player or enemy)

### How It Works:

**Local Player Shoots:**
1. Client: Player presses shoot → bullet spawns INSTANTLY at player position
2. Client: Send input to server
3. Server: Receives input, simulates, spawns authoritative bullet
4. Server: Sends bullet spawn RPC to all clients
5. Client: Receives own bullet spawn → SKIPS (already have predicted one)
6. Other Clients: Receive spawn → create bullet from other player

**Remote Player/Enemy Shoots:**
1. Server: Entity shoots, spawns bullet, sends RPC
2. Client: Receives bullet spawn → creates bullet immediately
3. Bullet simulates locally (no interpolation lag)

### Result:
- ✅ Bullets spawn exactly where player is aiming (no lag)
- ✅ Bullets follow player movement instantly
- ✅ Other player bullets still spawn correctly
- ✅ Server remains authoritative (can still validate hits)

### Trade-offs:
- Bullets are not reconciled (no server correction)
- This is acceptable because bullets:
  - Have short lifetime (~3 seconds)
  - Move fast and predictably
  - Visual feedback matters more than perfect sync
  - Hit detection still happens on server
