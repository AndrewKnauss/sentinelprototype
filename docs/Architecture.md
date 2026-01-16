# Architecture Overview

High-level design: **authoritative server** with **client-side prediction** for local player and **interpolation** for remote entities.

---

## Core System Interactions

```
┌──────────────┐         Input          ┌──────────────┐         Snapshot        ┌──────────────┐
│              │  ─────────────────────▶│              │  ─────────────────────▶│              │
│    CLIENT    │                        │    SERVER    │                        │    CLIENT    │
│              │◀─────────────────────  │              │◀─────────────────────  │              │
│              │   ACK + Snapshot       │              │    Input Received      │              │
└──────────────┘                        └──────────────┘                        └──────────────┘
     Local                                Authoritative                           Display
     Prediction                           Simulation                              Interpolation
```

---

## Major APIs

### Network (Net.gd - Autoload)

**Server Initialization**
```gdscript
Net.start_server(port: int, max_clients: int)
```

**Client Connection**
```gdscript
Net.connect_client(host: String, port: int)
```

**Signal Events**
- `peer_connected(peer_id: int)` – New player joined
- `peer_disconnected(peer_id: int)` – Player left
- `input_received(peer_id: int, cmd: Dictionary)` – Input from client
- `snapshot_received(snap: Dictionary)` – Full world state
- `ack_received(ack: Dictionary)` – Input acknowledged
- `spawn_received(payload: Dictionary)` – New entity spawned
- `despawn_received(peer_id: int)` – Entity destroyed
- `username_accepted(success: bool, message: String)` – Username validation result

**RPC Methods**
```gdscript
# Client → Server
Net.server_receive_input.rpc_id(1, input_dict)
Net.server_receive_username.rpc_id(1, username_string)

# Server → All Clients
Net.client_receive_snapshot.rpc(snapshot_dict)
Net.client_receive_ack.rpc_id(peer_id, ack_dict)
Net.spawn_entity.rpc(entity_spawn_payload)
Net.despawn_entity.rpc(net_id)
Net.client_spawn_player.rpc_id(peer_id, player_payload)
Net.client_despawn_player.rpc(peer_id)
```

---

### Replication (ReplicationManager - Autoload)

**Entity Registry**
```gdscript
Replication.register(entity: NetworkedEntity)
Replication.unregister(net_id: int)
Replication.get_entity(net_id: int) -> NetworkedEntity
Replication.get_all_entities() -> Array
```

**Snapshot Management**
```gdscript
Replication.build_snapshot() -> Dictionary  # Server: collect all entity states
Replication.apply_snapshot(states: Dictionary)  # Client: apply server truth
Replication.generate_id() -> int  # Generate net_id for server-spawned entities
```

**Entity Replication Interface** (inherit `NetworkedEntity`)
```gdscript
func get_replicated_state() -> Dictionary
func apply_replicated_state(state: Dictionary) -> void
```

---

### Persistence (PersistenceAPI - Autoload)

**Player Data**
```gdscript
Persistence.load_player(username: String) -> Dictionary
Persistence.save_player(player_data: Dictionary) -> void
```

**Structures**
```gdscript
Persistence.load_all_structures() -> Array
Persistence.save_structure(data: Dictionary) -> int  # Returns structure_id
Persistence.update_structure(id: int, data: Dictionary) -> void
Persistence.delete_structure(id: int) -> void
```

**Admin**
```gdscript
Persistence.wipe_all_players() -> void
Persistence.wipe_all_structures() -> void
Persistence.get_stats() -> Dictionary
```

---

## Entity Prediction Strategies

| Type | Strategy | Latency | Authority |
|------|----------|---------|-----------|
| **Local Player** | Client-side prediction + reconciliation | 0ms | Client samples input, server validates |
| **Remote Players** | Interpolation (2-tick delay) | ~33ms | Server authoritative |
| **Enemies** | Interpolation (2-tick delay) | ~33ms | Server AI-controlled |
| **Bullets** | Pure client-side prediction | 0ms | Client spawns, server validates damage |
| **Walls** | Static position, health-only updates | 0ms | Server authoritative |

---

## Data Structures

### Input Command
```gdscript
{
  "seq": 1001,           # Sequence number
  "mv": Vector2(-1, 0),  # Movement vector (normalized)
  "aim": Vector2(1, 0),  # Aim direction (normalized)
  "btn": 0x01            # Button flags (BTN_SHOOT, BTN_BUILD, etc)
}
```

### Snapshot (Server → Clients)
```gdscript
{
  "tick": 120,           # Server tick when snapshot was built
  "states": {
    "2": {"p": Vector2(100, 50), "r": 0.5, "h": 80.0, ...},   # net_id: state
    "3": {"p": Vector2(200, 100), "r": 1.0, "h": 150.0, ...}
  }
}
```

### ACK (Server → Client)
```gdscript
{
  "tick": 120,           # Snapshot tick this ACK corresponds to
  "ack_seq": 1001        # Last input sequence acknowledged
}
```

---

## Snapshot Processing

**How different entity types are handled when a snapshot arrives:**

### Players (Remote Only)

**Server sends:**
- Position, rotation, velocity
- Health, stamina
- Weapon state (ammo, equipped type)
- Username (for label display)

**Client receives:**
```gdscript
state = {"p": Vector2(...), "r": 0.5, "h": 100.0, "v": Vector2(...), "s": 50.0, "w": {...}, "u": "PlayerName"}
```

**Client processing:**
1. Add to interpolation buffer: `_snap_buffers[net_id].append({"tick": tick, "state": state})`
2. Keep buffer bounded to 40 snapshots
3. Later: interpolate position/rotation between surrounding snapshots
4. Apply health/stamina/weapon directly (no lerp)
5. Update label if username changed

**Why interpolation?**
- Remote players are server-authoritative (we don't have their input)
- Interpolating smooths their motion despite network jitter
- 2-tick delay ensures buffer always has surrounding snapshots

---

### Enemies (AI-Controlled)

**Server sends:**
- Position, rotation, velocity
- Health
- AI state (target, aggro status, aiming direction)

**Client receives:**
```gdscript
state = {"p": Vector2(...), "r": 0.5, "h": 80.0, "v": Vector2(...), "ai_state": {...}}
```

**Client processing:**
1. Same as remote players: add to interpolation buffer
2. Interpolate position/rotation between snapshots
3. Apply health directly
4. Apply full `apply_replicated_state()` to sync custom AI fields

**Why interpolation?**
- Server runs all AI logic (pathfinding, targeting, shooting)
- Client has no prediction data
- Smooth interpolation hides network latency

---

### Walls (Static Structures)

**Server sends:**
- Position (once, at spawn time only)
- Health (updated every snapshot)

**Client receives (at spawn):**
```gdscript
{
  "type": "wall",
  "net_id": 10001,
  "pos": Vector2(100, 50),
  "extra": {"builder": peer_id}
}
```

**Client receives (in snapshots):**
```gdscript
state = {"h": 150.0}  # Only health, no position
```

**Client processing:**
1. At spawn: Set position ONCE, add physics collision
2. In snapshots:
   - Check if health decreased (bullet damage)
   - Update health value
   - **Skip interpolation buffer entirely**
   - **Skip interpolation loop**

**Why NO interpolation?**
- Walls never move after placement (static geometry)
- Position is set once at spawn, never changes
- Interpolating a static position wastes CPU
- Only health changes, and that's applied directly
- **Performance gain**: ~40-50% fewer entities in interpolation loop

---

### Bullets (Client-Predicted)

**Server sends:**
- Spawn RPC (net_id, position, direction, owner, damage)
- Despawn RPC (when bullet expires or hits)

**Client receives (at spawn):**
```gdscript
{
  "type": "bullet",
  "net_id": 5001,
  "pos": Vector2(150, 75),
  "extra": {"dir": Vector2(1, 0), "owner": peer_id, "damage": 25.0}
}
```

**Client processing:**
1. Client already spawned predicted bullet instantly (at shoot time)
2. Server spawn RPC arrives slightly later
3. **Client ignores server bullet spawn** (already has predicted one)
4. Server bullet despawn RPC → Client removes bullet

**Why pure prediction?**
- Shooting needs instant visual feedback (0ms latency)
- Prediction is 100% accurate (deterministic movement)
- Server validates all damage (prevents cheating)
- No reconciliation needed (bullets are fire-and-forget)

**Code flow:**
```gdscript
# Client side (instant)
if btn & BTN_SHOOT:
  _spawn_predicted_bullet(pos, aim_dir, damage)  # Instant!

# Server side (validated)
if btn & BTN_SHOOT:
  _spawn_bullet(pos, aim_dir, owner, damage)      # Authoritative
  Net.spawn_entity.rpc(...)                        # Tell clients
```

---

### Local Player (Hybrid)

**Server sends:**
- All state (position, rotation, health, stamina, weapon, etc)

**Client receives:**
```gdscript
state = {"p": Vector2(...), "r": 0.5, "h": 100.0, "v": Vector2(...), "s": 50.0, "w": {...}}
```

**Client processing:**
1. **DO NOT** add to interpolation buffer (we predicted it)
2. Apply health immediately (server is authoritative)
3. Store in `_last_server_state` for reconciliation
4. When ACK arrives: compare predicted position vs server position
5. If mismatch > threshold: rewind + replay

**Why special handling?**
- We have the input (we sampled it)
- We predicted the motion already
- Server state is used only for validation and correction
- Health is applied immediately (no prediction race condition)

---

## Snapshot Build Process (Server)

```gdscript
func _physics_process(_delta):
  # 1. Simulate everything
  for peer_id in _players:
    player.apply_input(mv, aim, btn, dt)    # From client input
  
  for enemy in _enemies:
    enemy._update_ai()                      # Server AI runs
  
  # 2. Build snapshot
  var states = Replication.build_snapshot() # Calls get_replicated_state() on each entity
  
  var snapshot = {
    "tick": _server_tick,
    "states": states                        # Dictionary of net_id -> state
  }
  
  # 3. Broadcast
  Net.client_receive_snapshot.rpc(snapshot) # All clients
  
  for peer_id in Net.get_peers():
    var ack = {"tick": _server_tick, "ack_seq": _last_seq[peer_id]}
    Net.client_receive_ack.rpc_id(peer_id, ack)
```

**Key point:** `Replication.build_snapshot()` iterates all entities, calls their `get_replicated_state()`, and returns a flat dictionary. Entities filter themselves (walls only include health, bullets aren't included, etc).

---

## Snapshot Apply Process (Client)

```gdscript
func _on_snapshot(snap: Dictionary):
  _latest_tick = snap["tick"]
  var states = snap["states"]
  
  for net_id_str in states:
    var net_id = int(net_id_str)
    var state = states[net_id_str]
    var entity = Replication.get_entity(net_id)
    
    # Local player: store for reconciliation, apply health only
    if net_id == _my_id:
      _last_server_state = state
      _my_player.health = state["h"]
      continue
    
    # Bullets: skip (client-predicted)
    if entity is Bullet:
      continue
    
    # Walls: apply health only, no buffer
    if entity is Wall:
      entity.health = state["h"]
      continue
    
    # Remote players & enemies: buffer for interpolation
    _snap_buffers[net_id].append({"tick": _latest_tick, "state": state})
```

This is the critical branching logic that determines how each entity type is treated.


```
TICK 0  │ Client samples input, predicts locally, sends to server
        │ Server receives nothing yet
TICK 1  │ Server simulates players, enemies, bullets (using TICK 0 input)
        │ Server builds snapshot of all entities
        │ Server broadcasts snapshot + ACK
TICK 2  │ Client receives snapshot (tick 1 server state)
        │ Client stores for local player reconciliation
        │ Client buffers remote entities for interpolation
TICK 4  │ Client interpolates remote entities between buffered snapshots
        │ Renders at (latest_tick - 2) for smooth motion
```

---

## Critical Systems

### Client-Side Prediction (ClientMain.gd)

**Local Player Only**
- Apply input immediately (no wait for server)
- Store predicted state for each input sequence
- Detect position mismatch from server ACK
- If error > threshold: rewind + replay inputs

**Code Flow**
```gdscript
_send_and_predict(dt):
  1. Sample input (movement, aim, buttons)
  2. Send input RPC to server
  3. Apply input locally (player.apply_input)
  4. Store predicted state (_predicted_states[seq])
  5. Keep in _pending_inputs for replay if needed
```

### Server Reconciliation (ServerMain.gd)

**Authoritative Simulation**
- Receive client input via `_on_input_received()`
- Simulate: players (from input), enemies (AI), bullets, walls
- Build snapshot: `Replication.build_snapshot()`
- Broadcast to all clients
- Send per-client ACK with last input sequence

**Persistence**
- Auto-save every 30 seconds (`_autosave_all()`)
- Save on disconnect (`_save_player()`)
- Load structures at startup (`_load_all_structures()`)

### Interpolation (ClientMain.gd)

**Remote Entities (not local player, not walls)**
- Buffer snapshots: `_snap_buffers[net_id] = [{tick, state}, ...]`
- Render tick: `latest_tick - INTERP_DELAY_TICKS` (2-tick delay)
- Lerp position/rotation between surrounding snapshots
- Apply health/velocity directly (no lerp)

---

## Replication Contract

Every networked entity must implement:

```gdscript
func get_replicated_state() -> Dictionary
  # Return dict of state to sync (keys: "p"=position, "r"=rotation, "h"=health, etc)

func apply_replicated_state(state: Dictionary) -> void
  # Apply server state to this entity
  # Called by client during interpolation and reconciliation
```

**Auto-registration**: Entity calls `super._ready()` to auto-register with `Replication`.

---

## Authority Model

```gdscript
entity.authority == 1           # Server owns (all players, enemies, bullets, walls)
entity.authority == peer_id     # Client owns for prediction (local player only)

# Check authority:
if entity.is_authority():       # True if I control this entity
  # Can apply local prediction
```

---

## Performance Targets

- **Tick Rate**: 60 FPS (16.67ms per tick)
- **Snapshot Buffer**: 40 snapshots (~666ms history)
- **Pending Input Buffer**: 256 inputs (~4.2s max)
- **Reconciliation Threshold**: 5 units (position error)
- **Interpolation Delay**: 2 ticks (~33ms)

---

## Common Workflows

### Add New Networked Entity Type

1. Create `scripts/entities/MyEntity.gd` extending `NetworkedEntity`
2. Implement `get_replicated_state()` and `apply_replicated_state()`
3. Server spawns via `Replication.register(entity)`
4. Server broadcasts spawn via `Net.spawn_entity.rpc(payload)`
5. Client receives spawn, instantiates, applies initial state

### Add New Player Field

1. Add to `Player.get_replicated_state()` with short key (e.g., "s" for stamina)
2. Add to `Player.apply_replicated_state()` to restore it
3. Field now syncs automatically every snapshot

### Debug Network Issues

- Press **F3** for network overlay (FPS, ping, reconciles/sec, entity counts)
- Enable logging: `Log.network()`, `Log.entity()`, `Log.reconcile()`
- Check `GameConstants.RECONCILE_POSITION_THRESHOLD` and `INTERP_DELAY_TICKS`

