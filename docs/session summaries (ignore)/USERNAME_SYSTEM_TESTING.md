# Username System - Testing Guide

## Quick Test (5 Minutes)

### 1. Start Test Session
```bash
start_test_session.bat
```

**Expected**:
- Server starts
- 3 clients auto-connect with usernames: Alice, Bob, Charlie
- All clients join without showing username dialog (command-line usernames used)
- Console shows: "Username 'alice' accepted for peer {id}"

### 2. Test Username Persistence
**On Alice's client**:
- Move to a specific location (e.g., top-left corner)
- Build 2-3 walls
- **Close Alice's window**

**Expected**:
- Server console shows: "Saved player 'alice' (peer {id}) on disconnect"

**Reconnect Alice**:
- Run: `run_client_local.bat Alice`

**Expected**:
- Console shows: "Using username from command line: Alice"
- Console shows: "Loaded player 'alice' (peer {id}): pos={...}, hp=..."
- Alice spawns at previous location (NOT random spawn)
- Walls are still present

### 3. Test Username Dialog
**Without providing username**:
- Run: `run_client_local.bat` (no username arg)

**Expected**:
- Client connects to server
- Username input dialog appears
- Try invalid username "ab" → Error: "Username must be at least 3 characters"
- Try invalid username "test!" → Error: "Username can only contain letters, numbers, and underscores"
- Try valid username "TestUser" → Dialog shows "Connecting..."
- Server validates → Dialog shows "Welcome, TestUser!"
- Dialog disappears after 1 second
- Player spawns in game

### 4. Test Username Collision
**With Bob still connected**:
- Run: `run_client_local.bat Bob`

**Expected**:
- Console shows: "Username 'bob' already connected"
- Server rejects with error: "Username already in use"
- Client shows error in dialog (if using UI) or logs (if command-line)

**After Bob disconnects**:
- Run: `run_client_local.bat Bob` again

**Expected**:
- Username accepted (Bob is no longer connected)
- Loads Bob's saved data from previous session

### 5. Test Admin Commands
**On server window**:
- Press **F7**

**Expected**:
```
=== PERSISTENCE STATS ===
Players in DB: 4
Structures in DB: 2
Players online: 3
Walls spawned: 2
========================
```

- Press **F6** (wipe player data)
- Press **F7** again

**Expected**:
```
Players in DB: 0  (wiped)
Structures in DB: 2  (unchanged)
...
```

**Disconnect and reconnect Alice**:

**Expected**:
- Treated as new player (random spawn)
- Previous save data is gone

## Test Cases

### ✅ Valid Usernames
- "Alice"
- "Bob123"
- "Test_User"
- "abc" (minimum length)
- "SixteenCharsLong" (maximum length)

### ❌ Invalid Usernames
- "ab" (too short)
- "ThisIsTooLongForUsername" (too long)
- "test!" (special character)
- "user name" (space)
- "admin" (reserved name)
- "" (empty)

## Command-Line Usage

### Single Client with Username
```bash
run_client_local.bat Alice
```

### Single Client without Username (shows dialog)
```bash
run_client_local.bat
```

### Test Session (3 clients with usernames)
```bash
start_test_session.bat
```

## File Locations

**Player saves**:
```
C:\Users\{YourName}\AppData\Roaming\Godot\app_userdata\SentinelPrototype\saves\players\
├── alice.json
├── bob.json
├── charlie.json
└── testuser.json
```

**Structure saves**:
```
C:\Users\{YourName}\AppData\Roaming\Godot\app_userdata\SentinelPrototype\saves\
└── structures.json
```

## Troubleshooting

### "Username validation failed"
- Check console for specific error
- Ensure username is 3-16 characters
- Only use letters, numbers, underscore

### "Username already in use"
- Another client is connected with that username
- Wait for them to disconnect or use different username

### Dialog doesn't appear
- Check if --username was provided in command line
- Check console for "Using username from command line: {username}"

### Player doesn't load saved data
- Check that username matches exactly (case-insensitive)
- Verify save file exists in `saves/players/{username}.json`
- Check server console for "Loaded player '{username}'" message

## Expected Console Messages

### Server (successful login)
```
Peer {id} connected, waiting for username...
Received username 'Alice' from peer {id}
Username 'alice' accepted for peer {id}
New player 'alice' (peer {id}) created at (500, 300)
```

### Server (returning player)
```
Peer {id} connected, waiting for username...
Received username 'Alice' from peer {id}
Username 'alice' accepted for peer {id}
Loaded player 'alice' (peer {id}): pos=(512.5, 384.2), hp=85.0
```

### Client (command-line username)
```
My ID is {id}
Using username from command line: Alice
Submitting username: Alice
Username result: Success - Welcome, Alice!
```

### Client (dialog username)
```
My ID is {id}
Submitting username: TestUser
Username result: Success - Welcome, TestUser!
```

## Success Criteria
- [✅] Alice/Bob/Charlie auto-login via command-line
- [✅] Username dialog shows when no --username provided
- [✅] Invalid usernames rejected with clear errors
- [✅] Duplicate usernames rejected
- [✅] Usernames persist across sessions (position restored)
- [✅] Structures save with owner_username
- [✅] Admin commands work (F5/F6/F7)
- [✅] Graceful shutdown saves all data

## Known Issues
- Username dialog may briefly appear before auto-hiding if --username provided (harmless)
- Case-insensitive matching means "Alice" and "alice" are same username (intended)

## Next Steps After Testing
1. Test with 5+ different usernames
2. Verify save files are created correctly
3. Test server restart with persistent players
4. Move on to Session 5: Loot & Inventory System
