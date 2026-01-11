# TODO - Sentinel Prototype

## Live Game
**URL**: https://woolachee.itch.io/sentinel  
**Server**: web-production-5b732.up.railway.app:443

---

## Immediate Polish (Make it Feel Good)

### Visual Feedback
- [ ] Muzzle flash when shooting
- [ ] Bullet impact particles (hit walls/enemies/players)
- [ ] Damage numbers floating up
- [ ] Screen shake on taking damage
- [ ] Death animation/effect
- [ ] Footstep particles when moving

### Audio
- [ ] Shooting sound
- [ ] Hit sound (different for wall/enemy/player)
- [ ] Footsteps
- [ ] Enemy alert sound
- [ ] Death sound
- [ ] Background ambience

### UI Improvements
- [ ] Health bar visible always (not just on entities)
- [ ] Ammo/cooldown indicator
- [ ] Minimap (small corner map)
- [ ] Kill feed (X killed Y)
- [ ] Player count display
- [ ] Ping/latency display

---

## Core Gameplay Loop

### Loot System
- [ ] Item drops (from enemies, world spawns)
- [ ] Pickup interaction (E key)
- [ ] Inventory UI (grid-based)
- [ ] Item types: weapons, ammo, resources, armor
- [ ] Drop loot on death

### Resource Gathering
- [ ] Resource nodes (scrap metal, electronics)
- [ ] Gathering interaction (hold E)
- [ ] Resource inventory
- [ ] Visual feedback (progress bar, particles)

### Crafting
- [ ] Crafting UI (recipes)
- [ ] Basic recipes: bullets, walls, med kits
- [ ] Resource requirements
- [ ] Craft queue

### World Events
- [ ] Timed event spawner (every 5-10 min)
- [ ] Event types: Supply drop, Data cache, Machine patrol
- [ ] Event announcements (UI banner)
- [ ] High-value loot at events
- [ ] Event markers on map

---

## Anti-Bullying Systems

### Hot Loot
- [ ] Tag stolen/looted items as "hot"
- [ ] Hot loot increases AI aggro range
- [ ] Hot loot shows on minimap (visible to all)
- [ ] Hot loot can't be stored for X minutes
- [ ] Visual indicator (glowing red)

### Bounty System
- [ ] Track player kills vs player level difference
- [ ] Auto-bounty for killing lower-level players
- [ ] Bounty reward on bounty holder death
- [ ] Bounty UI indicator (target on map)
- [ ] Escalating bounty (multiple kills)

### Lawfulness Zones
- [ ] Map zones: Safe → Neutral → Lawless
- [ ] Safe: PvP disabled or heavy penalties
- [ ] Neutral: Moderate penalties (reputation loss)
- [ ] Lawless: No penalties, best loot
- [ ] Zone indicators on minimap/HUD

### Robin Hood Mechanics
- [ ] Raiding well-equipped bases gives more loot
- [ ] Raiding starter bases gives trash loot
- [ ] Reputation system (good/bad standing)
- [ ] Safe zone access based on reputation

---

## Progression System

### Player Levels
- [ ] XP from kills, gathering, crafting
- [ ] Level display on player
- [ ] Level-based stat boosts (HP, speed)
- [ ] Unlock crafting recipes by level

### Equipment Tiers
- [ ] Tier 1: Starter (pipe gun, scrap armor)
- [ ] Tier 2: Mid (rifle, metal armor)
- [ ] Tier 3: End (plasma gun, power armor)
- [ ] Visual differences per tier
- [ ] Tier affects damage/protection

### Base Building Expansion
- [ ] Multiple structure types (walls, doors, turrets)
- [ ] Structure health tiers (wood → metal → reinforced)
- [ ] Tool cupboard (claim area)
- [ ] Decay system (upkeep cost)
- [ ] Raiding tools (explosives, breach charges)

---

## Quality of Life

### Persistence
- [ ] Player data saves (inventory, position, level)
- [ ] Base persistence (structures remain)
- [ ] Server restart handling (graceful)
- [ ] Database setup (SQLite or Railway Postgres)

### Spawn System
- [ ] Multiple spawn points
- [ ] Spawn immunity (3 seconds)
- [ ] Spawn far from enemies
- [ ] Bed/sleeping bag respawn points

### Chat System
- [ ] Global chat
- [ ] Team/party chat
- [ ] Chat UI (message history)
- [ ] Chat commands (/help, /suicide)

---

## Performance & Polish

### Optimization
- [ ] Network bandwidth optimization
- [ ] Entity culling (don't send far entities)
- [ ] Chunk-based replication
- [ ] Object pooling (bullets, particles)

### Bug Fixes
- [ ] Test reconnection handling
- [ ] Fix any desync issues
- [ ] Collision edge cases
- [ ] Camera bounds (don't go outside world)

### Visuals
- [ ] Better sprites (replace colored squares)
- [ ] Tile-based map (ground textures)
- [ ] Lighting system (day/night cycle)
- [ ] Weather effects (optional)

---

## Recommended Priority Order

### Phase 1: Feel Good (Week 1)
1. Visual feedback (muzzle flash, particles, shake)
2. Audio (shooting, hits, footsteps)
3. UI improvements (health bar, minimap, kill feed)

### Phase 2: Core Loop (Week 2-3)
4. Loot system (drops, pickup, inventory)
5. Resource gathering
6. Basic crafting
7. World events

### Phase 3: Anti-Bullying (Week 4)
8. Hot loot mechanics
9. Bounty system
10. Lawfulness zones

### Phase 4: Progression (Week 5-6)
11. Player levels + XP
12. Equipment tiers
13. Base building expansion

### Phase 5: Polish (Ongoing)
14. Persistence/saves
15. Performance optimization
16. Better art assets

---

## Quick Wins (Do These First)

- [ ] Muzzle flash + shooting sound (instant feedback)
- [ ] Screen shake on damage
- [ ] Health bar always visible
- [ ] Kill feed
- [ ] Minimap
- [ ] Simple loot drops from enemies
- [ ] Basic pickup system

**Start here ↑ to make game feel alive immediately**
