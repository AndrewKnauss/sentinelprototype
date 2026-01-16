# Persistence System Testing Checklist

## Manual Testing Steps

### 1. New Player Creation
- [ ] Start server
- [ ] Connect client
- [ ] **Expected**: Player spawns at random position
- [ ] **Expected**: Console shows "New player {id} created at {pos}"
- [ ] **Expected**: `user://saves/players/{id}.json` file is created
- [ ] Verify JSON contains: position, health=100.0, level=1

### 2. Player Position Persistence
- [ ] Connect client, move to a specific location (e.g., top-left corner)
- [ ] Disconnect client
- [ ] **Expected**: Console shows "Saved player {id} on disconnect"
- [ ] Reconnect same client
- [ ] **Expected**: Console shows "Loaded player {id}: pos={...}, hp=..."
- [ ] **Expected**: Player spawns at previous location (NOT random spawn)

### 3. Structure Persistence
- [ ] Connect client
- [ ] Build 3-5 walls in different locations
- [ ] **Expected**: `user://saves/structures.json` is created
- [ ] Verify JSON contains wall data (position, health, owner)
- [ ] **Restart server** (close and relaunch)
- [ ] Reconnect client
- [ ] **Expected**: All walls are still present in same locations

### 4. Autosave System
- [ ] Connect client
- [ ] Move player to new position
- [ ] Wait 30 seconds (watch console)
- [ ] **Expected**: Console shows "Autosave started..." and "Autosaved {n} players, {n} structures"
- [ ] Check `user://saves/players/{id}.json` - position should be updated
- [ ] Build a wall
- [ ] Wait 30 seconds
- [ ] **Expected**: Console shows autosave with 1+ structures
- [ ] Check `user://saves/structures.json` - new wall should be present

### 5. Structure Destruction
- [ ] Build a wall
- [ ] Note the wall's position
- [ ] Destroy the wall (shoot until health=0)
- [ ] **Expected**: Console shows wall destroyed
- [ ] Check `user://saves/structures.json`
- [ ] **Expected**: Wall is removed from JSON file

### 6. Admin Commands (F5 - Wipe Structures)
- [ ] Build 3+ walls
- [ ] Press **F5** on server
- [ ] **Expected**: Console shows "ADMIN: Wiping all structures..."
- [ ] **Expected**: All walls disappear from game
- [ ] Check `user://saves/structures.json`
- [ ] **Expected**: File shows empty structures array: `{"structures": [], "next_id": 1}`
- [ ] Restart server
- [ ] **Expected**: No walls spawn (clean slate)

### 7. Admin Commands (F6 - Wipe Players)
- [ ] Connect client, move around, disconnect
- [ ] Check `user://saves/players/` - should have player file
- [ ] Press **F6** on server
- [ ] **Expected**: Console shows "ADMIN: Wiping all player data..."
- [ ] Check `user://saves/players/` - should be empty
- [ ] Reconnect client
- [ ] **Expected**: Player spawns at random position (treated as new player)

### 8. Admin Commands (F7 - Show Stats)
- [ ] Connect 2 clients
- [ ] Build 3 walls
- [ ] Press **F7** on server
- [ ] **Expected**: Console shows:
  ```
  === PERSISTENCE STATS ===
  Players in DB: 2
  Structures in DB: 3
  Players online: 2
  Walls spawned: 3
  ========================
  ```

### 9. Graceful Shutdown
- [ ] Connect client, move to specific position
- [ ] Build 2-3 walls
- [ ] Close server window (X button or Ctrl+C)
- [ ] **Expected**: Console shows "Server shutting down, saving all data..."
- [ ] **Expected**: Console shows "Shutdown save complete: {n} players, {n} structures"
- [ ] Restart server
- [ ] Reconnect client
- [ ] **Expected**: Player at saved position, walls still present

### 10. Multiple Players Persistence
- [ ] Connect 3 clients (different peer IDs)
- [ ] Move each to different corner of map
- [ ] Each client builds 1-2 walls
- [ ] Disconnect all clients
- [ ] **Expected**: 3 player JSON files created
- [ ] **Expected**: structures.json contains 3-6 walls
- [ ] Reconnect all 3 clients
- [ ] **Expected**: Each spawns at their saved position
- [ ] **Expected**: All walls present

### 11. Health Persistence
- [ ] Connect client
- [ ] Take damage from enemy (reduce health to ~50)
- [ ] Disconnect
- [ ] Check `user://saves/players/{id}.json` - health should be ~50
- [ ] Reconnect
- [ ] **Expected**: Player spawns with ~50 health (NOT 100)

### 12. Crash Recovery (Autosave Test)
- [ ] Connect client, move to position A
- [ ] Wait for autosave (30s)
- [ ] Move to position B (do NOT wait for autosave)
- [ ] **Kill server process** (Task Manager or `kill -9`)
- [ ] Restart server
- [ ] Reconnect client
- [ ] **Expected**: Player spawns at position A (last autosave)
- [ ] **Note**: Position B was never saved (expected data loss)

## Edge Cases

### 13. Rapid Disconnect/Reconnect
- [ ] Connect client
- [ ] Immediately disconnect (before autosave)
- [ ] Reconnect within 1 second
- [ ] **Expected**: No errors, player position saved/loaded correctly

### 14. Structure Deletion During Autosave
- [ ] Build 5 walls
- [ ] Wait for autosave to start (watch console)
- [ ] During "Autosave started..." message, destroy a wall
- [ ] **Expected**: No crashes or errors
- [ ] **Expected**: Autosave completes successfully
- [ ] Check structures.json - should reflect current state

### 15. Empty Database Restart
- [ ] Press F6 to wipe players
- [ ] Press F5 to wipe structures
- [ ] Restart server
- [ ] **Expected**: Server starts successfully
- [ ] **Expected**: Console shows "No structures found in database"
- [ ] Connect client
- [ ] **Expected**: Fresh spawn (new player)

### 16. Corrupted JSON Recovery
- [ ] Manually edit `user://saves/structures.json` to be invalid JSON: `{corrupt`
- [ ] Restart server
- [ ] **Expected**: Console shows error parsing JSON
- [ ] **Expected**: Server continues running (doesn't crash)
- [ ] **Expected**: No structures spawn (graceful fallback)

## Performance Testing

### 17. Autosave Performance (10 Players + 100 Walls)
- [ ] Connect 10 clients (run multiple instances or use test tool)
- [ ] Build 100 walls total (10 per player)
- [ ] Wait for autosave
- [ ] **Monitor**: Autosave should complete in <500ms
- [ ] **Monitor**: No frame drops or lag spikes
- [ ] **Expected**: Console shows "Autosaved 10 players, 100 structures"

### 18. Large Structure Count
- [ ] Build 500+ walls (may require increasing spawn limit)
- [ ] Restart server
- [ ] **Monitor**: Server startup time
- [ ] **Expected**: All 500 walls load successfully
- [ ] **Expected**: Startup completes in <5 seconds
- [ ] **Note**: If >10s startup, consider SQLite migration

## File System Checks

### 19. Save Directory Creation
- [ ] Delete `user://saves/` directory entirely
- [ ] Start server
- [ ] **Expected**: Directories auto-created:
  - `user://saves/`
  - `user://saves/players/`
  - `user://saves/inventory/`
- [ ] **Expected**: `structures.json` created

### 20. File Permissions
- [ ] Check all JSON files are readable/writable
- [ ] Verify file contents are properly formatted (use JSON validator)
- [ ] Verify timestamps in player data (`last_login` field)

## Regression Tests

### 21. Existing Gameplay Still Works
- [ ] Player movement works normally
- [ ] Shooting works normally
- [ ] Enemy AI works normally
- [ ] Wall building works normally
- [ ] Network sync works normally (no new desyncs)

### 22. No Performance Degradation
- [ ] Compare FPS before/after persistence system
- [ ] **Expected**: No noticeable FPS drop
- [ ] **Expected**: Network latency unchanged
- [ ] **Expected**: Memory usage reasonable (<100MB increase)

## Success Criteria
- [ ] All 22 tests pass
- [ ] No crashes or errors
- [ ] Data persists correctly across sessions
- [ ] Autosave is reliable and performant
- [ ] Admin commands work as expected
- [ ] Graceful shutdown saves all data

## Known Limitations (Expected Behavior)
- Inventory not yet implemented (placeholder in code)
- Level/XP/Currency not yet implemented (fields exist but unused)
- Only last 30-second autosave survives crash (data loss window)
- SQLite migration needed if >50 concurrent players

## Next Steps After Testing
1. Fix any bugs found
2. Optimize autosave if performance issues
3. Consider reducing autosave interval to 10-15s (production setting)
4. Implement inventory persistence (Session 5)
5. Add player name field (currently auto-generated)
