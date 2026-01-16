# Quick Test Guide - Loot System

## How to Test

### Start Game
```bash
cd C:\git\sentinelprototype
start_test_session.bat
```
This starts 1 server + 3 clients (Alice, Bob, Charlie)

### Test Checklist

#### 1. Kill Enemy → Item Drops ✅
- Move to enemy
- Shoot until dead (LMB)
- **EXPECT**: Item spawns at death location
- **SEE**: Colored square (rarity color)
- **SEE**: "x3" label if quantity > 1

#### 2. Pickup Prompt ✅
- Walk near item (within 50 pixels)
- **EXPECT**: Yellow text appears: "[E] Scrap Metal x3"
- Walk away
- **EXPECT**: Prompt disappears

#### 3. Pick Up Item ✅
- Walk near item
- Press E
- **EXPECT**: Item disappears instantly (client prediction)
- **CHECK CONSOLE**: "[ENTITY] Player 2 picked up 3x scrap_metal"

#### 4. Inventory Full ✅
- Kill 20+ enemies (fill all 20 slots)
- Try to pick up another item
- **EXPECT**: Item reappears after 0.5 seconds
- **CHECK CONSOLE**: "[WARN] Player 2 inventory full, could not pickup scrap_metal"

#### 5. Different Enemy Types ✅
Kill each enemy type, observe different loot:

**Normal** (white):
- Mix of scrap, electronics, ammo, bandages

**Scout** (orange, fast):
- Less loot, mostly light ammo

**Tank** (gray, slow, armored):
- Lots of scrap (3-6x)
- Advanced circuits (rare)
- Heavy ammo

**Sniper** (purple, laser):
- Electronics (2-4x)
- Energy cells
- Advanced circuits

**Swarm** (cyan, tiny, fast):
- Minimal (1-2 scrap)

## Debug Commands

| Key | Action |
|-----|--------|
| F3  | Toggle network diagnostics |
| F4  | Toggle collision shapes |
| F5  | (Server) Wipe all structures |
| F6  | (Server) Wipe all players |
| F7  | (Server) Show stats |

## Console Logs to Watch

### Server
```
[ENTITY] Enemy 15 died
[ENTITY] Spawned item_drop with net_id 42 at (450, 300)
[ENTITY] Player 2 picked up 3x scrap_metal
[WARN] Player 2 inventory full, could not pickup electronics
```

### Client
```
[ENTITY] Received spawn_entity: {type: item_drop, net_id: 42, ...}
[ENTITY] Spawned item_drop with net_id 42 at (450, 300)
[ENTITY] Requesting pickup of item 42 (scrap_metal x3)
[WARN] Pickup failed for item 42 (timeout)
```

## Known Limitations

❌ **Cannot see inventory contents** (no UI yet)
- Use console logs to verify items added
- Check: `[ENTITY] Player 2 picked up 3x scrap_metal`

❌ **Items lost on death** (no drop-on-death yet)
- Player dies → inventory cleared (not dropped)

❌ **No way to drop items** (no drop button yet)
- Can only pick up, can't get rid of items

❌ **No item persistence** (inventory not saved)
- Player disconnect → inventory lost
- Server restart → items on ground lost

✅ **Working**: Pickup, stacking, loot tables, network sync

## Item List

### Resources (stackable 999)
- Scrap Metal (common, gray)
- Electronics (uncommon, blue)
- Advanced Circuits (rare, purple)
- AI Core (epic, orange)

### Ammo (stackable 999)
- Light Ammo (common, tan)
- Heavy Ammo (uncommon, red)
- Energy Cells (rare, cyan)

### Consumables
- Bandage (common, white) - stack 10
- Medkit (uncommon, red) - stack 5
- Stimpack (rare, green) - stack 3

### Buildables
- Wood Wall (common, brown) - stack 50
- Metal Wall (uncommon, gray) - stack 50
- Door (uncommon, brown) - stack 20

## Next Test (After Session 7)

- Press I → inventory UI opens
- See 20 slots in 4x5 grid
- Hover item → tooltip shows details
- Die → items scatter on ground
- F8 → give item menu
