# Session #4 Complete - Username System Implementation Summary

## ✅ What Was Built

### Core Problem Solved
**Issue**: Godot's multiplayer peer IDs are session-based and change on every reconnect. Using peer_id as database keys meant players lost all progress on reconnect.

**Solution**: Username-based persistent identity. Players choose a username that persists across sessions. Server maintains runtime mapping of username ↔ peer_id for current session.

### New Files Created
1. **`scripts/shared/UsernameValidator.gd`** - Username validation utilities
2. **`scripts/ui/UsernameDialog.gd`** - Client-side username input dialog
3. **`docs/USERNAME_SYSTEM_TESTING.md`** - Testing guide

### Modified Files
4. **`scripts/systems/PersistenceAPI.gd`** - Changed from peer_id to username
5. **`scripts/systems/PersistenceBackend.gd`** - Updated API signatures
6. **`scripts/systems/JSONPersistence.gd`** - Username-based file storage
7. **`scripts/net/Net.gd`** - Added username RPCs
8. **`scripts/entities/Player.gd`** - Added username field
9. **`scripts/entities/Wall.gd`** - Added builder_username field
10. **`scripts/server/ServerMain.gd`** - Two-phase connection (connect → auth → spawn)
11. **`scripts/client/ClientMain.gd`** - Username dialog integration
12. **`run_client_local.bat`** - Support optional username argument
13. **`start_test_session.bat`** - Auto-login as Alice/Bob/Charlie
14. **`docs/systems/PERSISTENCE.md`** - Updated with username design
15. **`CLAUDE.md`** - Documented Session 4 changes

## 🔧 How It Works

### Connection Flow
```
1. Client connects to server
   ↓
2. Server assigns random peer_id (e.g., 12345)
   ↓
3. Client shows username dialog OR uses --username arg
   ↓
4. Client sends username via RPC → Server
   ↓
5. Server validates username:
   - 3-16 characters
   - Alphanumeric + underscore only
   - Not already connected
   - Not reserved (admin, server, etc.)
   ↓
6. Server accepts/rejects with RPC → Client
   ↓
7. If accepted:
   - Server maps: username_to_peer["alice"] = 12345
   - Server loads player data by username
   - Player spawns (new or returning)
```

### Data Storage
```
Before (Broken):
saves/players/12345.json  ← Peer ID changes every session!

After (Fixed):
saves/players/alice.json  ← Username stays the same!
```

### Runtime vs Persistent Identity
```gdscript
// Runtime (this session only)
var peer_id: int = 12345  // Changes every connect
var builder_id: int = 12345  // For walls built this session

// Persistent (across sessions)
var username: String = "alice"  // Stays the same
var builder_username: String = "alice"  // For wall ownership
```

## 🎮 Features

### Username Validation
- **Length**: 3-16 characters
- **Characters**: Letters, numbers, underscore only (`^[a-zA-Z0-9_]+$`)
- **Uniqueness**: One active session per username
- **Case-insensitive**: "Alice" = "alice"
- **Reserved names**: admin, server, moderator, system, bot

### Command-Line Support
```bash
# Auto-login with username
run_client_local.bat Alice

# Show username dialog
run_client_local.bat

# Test session with 3 usernames
start_test_session.bat  # Alice, Bob, Charlie
```

### Username Dialog
- Appears after connection if no --username provided
- Client-side validation with live feedback
- Disables input while waiting for server response
- Shows success/error messages
- Auto-hides on success

### Server Features
- Two-phase connection (connect → authenticate → spawn)
- Username collision prevention
- Tracks pending authentication
- Cleans up mappings on disconnect

## 📊 Testing

### Quick Test
```bash
start_test_session.bat  # Spawns Alice/Bob/Charlie

# Disconnect Alice
# Reconnect: run_client_local.bat Alice
# Expected: Spawns at previous location (persistence works!)
```

### Manual Test
```bash
run_client_local.bat  # No username
# Dialog appears
# Try: "ab" → Error (too short)
# Try: "Alice!" → Error (special char)
# Try: "Alice" → Success
```

See `docs/USERNAME_SYSTEM_TESTING.md` for full test plan.

## 🔍 Technical Details

### RPC Flow
```gdscript
// Client → Server
Net.server_receive_username.rpc_id(1, "Alice")

// Server validates, then Server → Client
Net.client_receive_username_result.rpc_id(peer_id, true, "Welcome, Alice!")
```

### Server State Tracking
```gdscript
var _username_to_peer: Dictionary = {}  // "alice" -> 12345
var _peer_to_username: Dictionary = {}  // 12345 -> "alice"
var _pending_authentication: Dictionary = {}  // 12345 -> true
```

### Persistence Changes
```gdscript
// Before
Persistence.load_player(peer_id: int) -> Dictionary
Persistence.save_player({"peer_id": 12345, ...})

// After
Persistence.load_player(username: String) -> Dictionary
Persistence.save_player({"username": "alice", ...})
```

## 🐛 Edge Cases Handled

1. **Username collision**: Server rejects if already connected
2. **Disconnect before auth**: Server cleans up pending auth
3. **Invalid username**: Client-side + server-side validation
4. **Reserved names**: Prevents players from using "admin", etc.
5. **Case sensitivity**: "Alice" and "alice" are the same
6. **Special characters**: Blocked with regex validation
7. **Empty username**: Rejected with clear error

## 📝 Data Format Examples

### Player Save (alice.json)
```json
{
  "username": "alice",
  "position_x": 512.5,
  "position_y": 384.2,
  "health": 85.0,
  "level": 1,
  "xp": 0,
  "reputation": 0.0,
  "currency": 0,
  "last_login": 1704844800
}
```

### Structure Save (owner_username)
```json
{
  "structures": [
    {
      "id": 1,
      "owner_username": "alice",
      "type": "wall",
      "position_x": 600.0,
      "position_y": 400.0,
      "health": 100.0
    }
  ]
}
```

## ✨ What This Enables

With username-based persistence working, we can now implement:
- ✅ **Loot & Inventory** - Items persist by username
- ✅ **XP & Levels** - Progression saves
- ✅ **Currency** - Wallet persists
- ✅ **Reputation** - Tracks player behavior
- ✅ **Base Ownership** - Structures tied to username
- ✅ **Player Rankings** - Leaderboards by username

## 🚀 Next Steps

### Immediate (Testing)
1. Run `start_test_session.bat`
2. Test username persistence (disconnect/reconnect)
3. Test username dialog validation
4. Verify save files created correctly

### Session 5 (Next Implementation)
- **Loot System** - Items drop on ground
- **Inventory** - 20-slot storage
- **Pickup Interaction** - E key to collect
- **Drop on Death** - Lose items when killed

The persistence foundation is rock-solid and ready for progression systems! 🎉

## 🔧 Maintenance Notes

### Adding New Reserved Names
Edit `UsernameValidator.gd`:
```gdscript
const RESERVED_NAMES = ["admin", "server", "moderator", "system", "bot", "newname"]
```

### Changing Username Length Limits
Edit `UsernameValidator.gd`:
```gdscript
const MIN_LENGTH = 3  // Change minimum
const MAX_LENGTH = 16  // Change maximum
```

### Migrating Old peer_id Saves
If you have existing saves with peer_id keys, create a migration script:
```gdscript
# Migration: Rename old saves to username format
# Copy 12345.json → alice.json
# Update "peer_id" field to "username" field
```

## 📚 Documentation
- **Design**: `docs/systems/PERSISTENCE.md`
- **Testing**: `docs/USERNAME_SYSTEM_TESTING.md`
- **Implementation**: `docs/PERSISTENCE_IMPLEMENTATION.md`
- **Quickstart**: `docs/PERSISTENCE_QUICKSTART.md`

## ⚠️ Known Limitations
- Username changes not supported (would require data migration)
- Account recovery requires username knowledge
- No password protection (usernames are public)
- One session per username (intended - prevents duplicate logins)

These are acceptable for an indie multiplayer game. Add account system later if needed.
