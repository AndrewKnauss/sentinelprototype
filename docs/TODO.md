# TODO - Sentinel Prototype

## Live Game
**URL**: https://woolachee.itch.io/sentinel  
**Server**: web-production-5b732.up.railway.app:443

---

## CRITICAL PATH (Do First)

### Session 3: Core Fixes & Sprint
- [x] Fix dash input (use just_pressed) - **DONE**
- [x] **Sprint system** (Shift key, stamina bar) - **DONE**
- [x] **Weapon system** (5 types, switching, ammo) - **DONE**
- [x] **Enemy variety** (Scout, Tank, Sniper, Swarm, Normal) - **DONE**

### Session 4: Persistence Foundation
**MUST DO BEFORE OTHER SYSTEMS**
- [ ] **SQLite database setup** - See `PERSISTENCE.md`
- [ ] Player save/load (position, stats, inventory)
- [ ] Structure persistence (walls survive restart)
- [ ] Autosave system (5 min intervals)
- [ ] Graceful shutdown handler

### Session 5: Loot & Inventory
- [ ] **Item system** (ItemData definitions) - See `LOOT_SYSTEM.md`
- [ ] ItemDrop entity (spawns, interpolation)
- [ ] Inventory component (20 slots)
- [ ] E-key pickup interaction
- [ ] Drop on death
- [ ] Inventory UI (grid display)

### Session 6: Base Building
- [ ] **Tool Cupboard** (ownership, authorization) - See `BASE_BUILDING.md`
- [ ] Building grid (local to cupboard, not world-global)
- [ ] Building mode (B key, ghost preview, rotation)
- [ ] Structure types (Foundation, Wall, Doorway, Stairs)
- [ ] Upkeep & decay system
- [ ] Raiding mechanics (destroy cupboard = claim)

---

## POLISH (Make it Feel Good)

### Visual Feedback
- [ ] Muzzle flash when shooting
- [ ] Bullet impact particles (walls/enemies/players)
- [ ] Screen shake on taking damage
- [ ] Death animation/effect
- [ ] Dash particles/trail
- [ ] Footstep particles

### Audio
- [ ] Shooting sound (per weapon type)
- [ ] Hit sound (wall/enemy/player variants)
- [ ] Footsteps
- [ ] Dash sound
- [ ] Enemy alert sound
- [ ] Death sound
- [ ] Background ambience

### UI Improvements
- [ ] Always-visible health bar (not just on entities)
- [ ] Stamina bar (sprint)
- [ ] Ammo counter + reload indicator
- [ ] Weapon icon display
- [ ] Minimap (corner, zone overlays)
- [ ] Kill feed (X killed Y)
- [ ] Player count display

---

## ANTI-GRIEFING SYSTEMS

### Hot Loot (Week 4)
See `HOT_LOOT_SYSTEM.md`
- [ ] Mark items hot on PvP kill
- [ ] 2x AI aggro range for hot carriers
- [ ] Map markers (visible to all)
- [ ] Storage prevention (5 min cooldown)
- [ ] Visual indicators (red glow, particles)

### Bounty System (Week 4)
See `BOUNTY_SYSTEM.md`
- [ ] Level-diff tracking (5+ = griefing)
- [ ] Auto-bounty on unfair kills
- [ ] Anti-farming cooldown (1 hour same-player)
- [ ] Escalating rewards (1.5x per kill)
- [ ] Map markers + notifications
- [ ] Decay over time (30 min no kills)

### Territory Control (Week 6)
See `ADVANCED_SYSTEMS.md`
- [ ] Control points (capture mechanics)
- [ ] Zone bonuses (craft speed, loot mult)
- [ ] Resource spawning (5 min intervals)
- [ ] Contested zones

### Lawfulness Zones (Week 7+)
See `LAWFULNESS_ZONES.md` - **DEFER UNTIL MAP EXPANSION**
- [ ] Zone definitions (Safe/Neutral/Lawless)
- [ ] PvP blocking (Safe zones)
- [ ] Reputation penalties (Neutral)
- [ ] Loot scaling by zone
- [ ] Visual overlays + minimap

---

## PROGRESSION SYSTEMS

### Player Levels & XP
See `ADVANCED_SYSTEMS.md`
- [ ] XP gain (kills, gathering, crafting, events)
- [ ] Level-up rewards (skill points)
- [ ] XP display (progress bar)

### Skill Tree (Week 5)
See `ADVANCED_SYSTEMS.md`
- [ ] 3 trees: Combat / Builder / Scavenger
- [ ] Skill UI (tree visualization)
- [ ] Skill point allocation
- [ ] Bonus application (health, damage, build cost, etc)

### World Events (Week 3)
See `WORLD_EVENTS.md`
- [ ] Event scheduler (10/15/20 min intervals)
- [ ] Supply Drop (crate + loot)
- [ ] Data Cache (hack terminal objective)
- [ ] Machine Patrol (elite enemy convoy)
- [ ] Announcement UI + minimap markers

---

## ADVANCED FEATURES

### Crafting & Workbench (Week 5)
See `ADVANCED_SYSTEMS.md`
- [ ] Workbench entity (3 tiers)
- [ ] Recipe definitions
- [ ] Crafting UI
- [ ] Research system (consume to learn)

### NPC Traders (Week 6)
See `ADVANCED_SYSTEMS.md`
- [ ] Trader entity (safe zones)
- [ ] Stock tables (rotating inventory)
- [ ] Buy/sell UI
- [ ] Reputation gating

### Status Effects (Week 4)
See `ADVANCED_SYSTEMS.md`
- [ ] Bleed (DoT from heavy hits)
- [ ] Poison (AI gas grenades)
- [ ] Slow (ice/tar areas)
- [ ] Radiation (environmental zones)
- [ ] Effect icons + timers

### Day-Night Cycle (Week 7)
See `ADVANCED_SYSTEMS.md`
- [ ] Time system (60x speed)
- [ ] Lighting updates
- [ ] Night modifiers (2x enemies, better loot)
- [ ] Weather system (rain, fog)

### Vehicles (Week 8+)
See `ADVANCED_SYSTEMS.md`
- [ ] Bike / Car / Truck
- [ ] Enter/exit mechanics
- [ ] Storage capacity
- [ ] Fuel system
- [ ] Raidable when parked

---

## PERFORMANCE & OPTIMIZATION

### Network
- [ ] Entity culling (don't sync distant entities)
- [ ] Snapshot compression
- [ ] Interest management (chunk-based)

### Rendering
- [ ] Object pooling (bullets, particles)
- [ ] Camera bounds (world limits)
- [ ] LOD system (optional)

---

## WEEK-BY-WEEK ROADMAP

### Week 1: Foundation
1. Sprint + stamina ✓
2. Weapon system (5 types)
3. Enemy variety (5 types)
4. **Polish pass** (muzzle flash, sounds, shake)

### Week 2: Persistence & Loot
5. **DATABASE SETUP** (critical)
6. Loot drops + inventory
7. Pickup interaction
8. Player/structure saves

### Week 3: Base Building
9. Tool Cupboard system
10. Building mode UI
11. Structure types
12. Upkeep/decay
13. **World Events** (supply drops, etc)

### Week 4: Anti-Griefing
14. Hot Loot system
15. Bounty system
16. Status effects

### Week 5: Progression
17. Skill tree
18. Crafting/Workbench
19. XP balancing

### Week 6: Endgame
20. Territory Control
21. NPC Traders
22. Advanced features

### Week 7+: Polish & Content
23. Day-Night cycle
24. Lawfulness zones (needs bigger map)
25. Vehicles
26. Art replacement

---

## SYSTEM DESIGN DOCS REFERENCE

All systems have detailed design docs in `/docs/systems/`:

- `LOOT_SYSTEM.md` - Item drops, inventory, pickup
- `HOT_LOOT_SYSTEM.md` - Anti-griefing via hot items
- `BOUNTY_SYSTEM.md` - Auto-bounties for unfair kills
- `WORLD_EVENTS.md` - Timed contests (supply drops, etc)
- `LAWFULNESS_ZONES.md` - Safe/Neutral/Lawless regions
- `PERSISTENCE.md` - SQLite save system
- `BASE_BUILDING.md` - Cupboard ownership, building mode
- `ENEMIES_AND_SPRINT.md` - 5 enemy types + sprint
- `WEAPON_SYSTEM.md` - 5 weapon types + switching
- `ADVANCED_SYSTEMS.md` - Skills, crafting, traders, vehicles, etc.

See `SYSTEM_DESIGN_INDEX.md` for overview.

---

## IMMEDIATE NEXT STEPS

**This Week (Session 4)**:
1. **DATABASE SETUP** - CRITICAL BLOCKER
   - SQLite integration
   - Player persistence (position, stats, inventory)
   - Structure persistence (walls survive restart)
   - Autosave system (5 min intervals)

**Next Week (Session 5)**:
1. Loot system foundation
2. Item drops + inventory
3. Base building (Tool Cupboard)

**Critical Rule**: Don't implement Hot Loot, Bounties, or Territory Control until Database is working.
