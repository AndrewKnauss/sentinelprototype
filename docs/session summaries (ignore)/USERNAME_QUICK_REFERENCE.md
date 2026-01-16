# Username System - Quick Reference

## Usage

### Start Clients with Usernames
```bash
# Auto-login as Alice
run_client_local.bat Alice

# Show username dialog
run_client_local.bat

# Test session (Alice/Bob/Charlie)
start_test_session.bat
```

### Username Rules
- **Length**: 3-16 characters
- **Allowed**: Letters, numbers, underscore (`a-zA-Z0-9_`)
- **Not Allowed**: Spaces, special characters, reserved names
- **Case**: Insensitive ("Alice" = "alice")

### Reserved Names
- admin
- server
- moderator
- system
- bot

## Key Files

### Code
- `scripts/shared/UsernameValidator.gd` - Validation logic
- `scripts/ui/UsernameDialog.gd` - Input dialog
- `scripts/server/ServerMain.gd` - Server-side auth
- `scripts/client/ClientMain.gd` - Client-side submission

### Data
- `saves/players/{username}.json` - Player data by username
- `saves/structures.json` - Structures with owner_username

### Docs
- `docs/USERNAME_SYSTEM_TESTING.md` - Full test guide
- `docs/USERNAME_SYSTEM_SUMMARY.md` - Implementation details
- `docs/systems/PERSISTENCE.md` - Design document

## RPC Flow

```
Client                          Server
  |                               |
  |-- server_receive_username -->|  (validate)
  |                               |
  |<- client_receive_username_result --|
  |                               |
(spawn player)              (spawn player)
```

## Validation Examples

### ✅ Valid
- Alice
- Bob123
- Test_User
- abc (min)
- SixteenCharsLong (max)

### ❌ Invalid
- ab (too short)
- ThisIsTooLongForUsername (too long)
- test! (special char)
- user name (space)
- admin (reserved)

## Testing Checklist

- [ ] Alice/Bob/Charlie auto-login
- [ ] Username dialog validation
- [ ] Duplicate username rejection
- [ ] Position persistence
- [ ] Structure owner_username saved
- [ ] Admin commands work (F5/F6/F7)

## Troubleshooting

**Dialog doesn't appear?**
→ Check if --username was in command line

**Username rejected?**
→ Check console for validation error

**Data not persisting?**
→ Verify save file: `saves/players/{username}.json`

**Already in use?**
→ Another client has that username

## Admin Commands (Server)

- **F5** - Wipe all structures
- **F6** - Wipe all player data
- **F7** - Show stats

## Console Messages

**Success**:
```
Username 'alice' accepted for peer 12345
New player 'alice' (peer 12345) created
```

**Collision**:
```
Username 'alice' already connected
```

**Invalid**:
```
Invalid username from peer 12345: {error}
```

## Quick Debug

**Check username mapping**:
```gdscript
// In ServerMain
print(_username_to_peer)  // "alice" -> 12345
print(_peer_to_username)  // 12345 -> "alice"
```

**Check save file**:
```
AppData/Roaming/Godot/app_userdata/SentinelPrototype/saves/players/
```

**Check console for**:
- "Using username from command line: {username}"
- "Username '{username}' accepted for peer {id}"
- "Loaded player '{username}'"
