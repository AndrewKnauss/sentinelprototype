# Quick Start - Testing Persistence

## 5-Minute Smoke Test

### 1. Start Server
```bash
start_test_session.bat
```

### 2. Test New Player
- Connect with client
- **Expected**: Console shows "New player {id} created"
- Move around, note your position
- Press **F7** on server window
- **Expected**: Shows "Players in DB: 1"

### 3. Test Disconnect Save
- Disconnect client (close window)
- **Expected**: Console shows "Saved player {id} on disconnect"
- Reconnect client
- **Expected**: Spawn at previous position (NOT random spawn)

### 4. Test Structure Persistence
- Build 3-5 walls
- Press **F7** on server
- **Expected**: Shows "Structures in DB: 3-5"
- **Close server window** (X button)
- **Expected**: Console shows "Shutdown save complete"
- Restart server
- Reconnect client
- **Expected**: All walls still present

### 5. Test Autosave
- Move to new position
- Wait 30 seconds (watch server console)
- **Expected**: Console shows "Autosave started..." then "Autosaved 1 players, {n} structures"
- Close server WITHOUT graceful shutdown (Task Manager kill)
- Restart server
- Reconnect client
- **Expected**: Spawn at autosaved position

### 6. Test Admin Commands
**F5 - Wipe Structures**:
- Press F5 on server
- **Expected**: All walls disappear
- **Expected**: Console shows "All structures wiped"

**F6 - Wipe Players**:
- Disconnect client
- Press F6 on server
- Reconnect client
- **Expected**: Spawns at random position (fresh player)

**F7 - Show Stats**:
- Press F7
- **Expected**: Shows player/structure counts

## ✅ Success Indicators

If these all work, persistence is functioning correctly:
- [✅] New players spawn random
- [✅] Returning players load saved position
- [✅] Structures survive restart
- [✅] Autosave triggers every 30s
- [✅] Admin commands work

## 🐛 Common Issues

### "Failed to open player file"
- **Cause**: Permissions issue
- **Fix**: Run as administrator or check `user://` directory permissions

### Structures don't load on restart
- **Cause**: `structures.json` corrupted or missing
- **Fix**: Check `AppData/Roaming/Godot/app_userdata/SentinelPrototype/saves/`
- **Fix**: Verify JSON is valid using online validator

### Autosave not triggering
- **Cause**: Server tick not running
- **Fix**: Ensure server is running in headless mode
- **Fix**: Check console for errors

### Players always spawn random (not loading)
- **Cause**: `Persistence` autoload not initialized
- **Fix**: Check `project.godot` has `Persistence` in autoload section
- **Fix**: Check console for "Backend initialized" message on startup

## 📂 Save File Locations

**Windows**:
```
C:\Users\{YourName}\AppData\Roaming\Godot\app_userdata\SentinelPrototype\saves\
```

**Linux**:
```
~/.local/share/godot/app_userdata/SentinelPrototype/saves/
```

**Mac**:
```
~/Library/Application Support/Godot/app_userdata/SentinelPrototype/saves/
```

## 🔍 Debugging

### View Player Data
1. Navigate to `user://saves/players/`
2. Open `{peer_id}.json` in text editor
3. Verify `position_x`, `position_y`, `health` values

### View Structure Data
1. Navigate to `user://saves/`
2. Open `structures.json` in text editor
3. Verify `structures` array contains wall data

### Watch Autosave in Real-Time
1. Start server
2. Connect client
3. Open `structures.json` in text editor with auto-refresh
4. Build walls and watch file update every 30 seconds

### Console Filtering
Look for these key messages:
- `[Persistence]` - Backend initialization
- `[NETWORK]` - Player connect/disconnect/save events
- `Autosave started` - Autosave trigger
- `ADMIN:` - Admin command execution

## 🎯 Ready for Session 5?

Once all tests pass, you're ready to implement:
- **Loot System** - Inventory persistence API is ready
- **Item Drops** - Can save/load player inventories
- **Base Building** - Tool Cupboard can use same structure persistence

The foundation is solid! 🚀
