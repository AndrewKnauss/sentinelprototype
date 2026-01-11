# Network Architecture Overview

## System Block Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         CLIENT                               │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  LOCAL PLAYER (Prediction)          REMOTE ENTITIES (Interp) │
│  ┌──────────────────────┐          ┌────────────────────┐   │
│  │ 1. Sample Input      │          │ Snapshot Buffer    │   │
│  │ 2. Send to Server ───┼──────┐   │ (2 tick delay)     │   │
│  │ 3. Predict Locally   │      │   │                    │   │
│  │ 4. Store State       │      │   │ Players, Enemies,  │   │
│  └──────────────────────┘      │   │ Walls              │   │
│           │                    │   └────────────────────┘   │
│           │                    │            │                │
│           ▼                    │            ▼                │
│  ┌──────────────────────┐      │   ┌────────────────────┐   │
│  │ Pending Inputs       │      │   │ Interpolate        │   │
│  │ Predicted States     │      │   │ (Lerp between      │   │
│  └──────────────────────┘      │   │  snapshots)        │   │
│           │                    │   └────────────────────┘   │
│           │                    │                             │
└───────────┼────────────────────┼─────────────────────────────┘
            │                    │
            │    NETWORK         │
            ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                         SERVER                               │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 1. Receive Input from Client                         │   │
│  │ 2. Simulate Player (Authoritative)                   │   │
│  │ 3. Simulate Enemies (AI)                             │   │
│  │ 4. Simulate Bullets & Walls                          │   │
│  │ 5. Build Snapshot (all entity states)                │   │
│  │ 6. Send Snapshot to ALL clients                      │   │
│  │ 7. Send ACK to each client (with their input seq)    │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                  │
└────────────────────────────┼──────────────────────────────────┘
                             │
                             ▼
            ┌────────────────────────────────┐
            │  Snapshot arrives at Client    │
            └────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
    ┌─────────────────────┐   ┌─────────────────────┐
    │  LOCAL PLAYER       │   │  REMOTE ENTITIES    │
    │  - Store for        │   │  - Add to buffer    │
    │    reconciliation   │   │  - Interpolate      │
    │  - Apply health     │   │                     │
    └─────────────────────┘   └─────────────────────┘
                │
                ▼
    ┌─────────────────────┐
    │  ACK arrives        │
    │  - Compare position │
    │  - Reconcile if     │
    │    mismatch         │
    └─────────────────────┘
```

## Entity Handling Strategies

| Entity Type    | Client Strategy              | Latency    | Notes                          |
|----------------|------------------------------|------------|--------------------------------|
| Local Player   | Client-Side Prediction       | 0ms        | Instant feedback               |
| Remote Players | Interpolation (2 tick delay) | ~33ms      | Smooth, no input data          |
| Enemies        | Interpolation (2 tick delay) | ~33ms      | Server-authoritative AI        |
| Walls          | Static (no interpolation)    | 0ms        | Position set once, health only |
| Bullets        | Pure Client Prediction       | 0ms        | No reconciliation needed       |

## Data Flow Timeline

```
Tick 0:  Client samples input
         ├─> Send to server (RPC)
         └─> Predict locally (instant)

Tick 1:  Server receives input
         ├─> Simulate player
         ├─> Build snapshot
         └─> Send snapshot + ACK

Tick 2:  Client receives snapshot
         ├─> Store local player state
         ├─> Apply health immediately
         └─> Buffer remote entities

Tick 2:  Client receives ACK
         ├─> Compare predicted vs server position
         └─> Reconcile if mismatch (rewind + replay)

Tick 4:  Client interpolates remote entities
         └─> Render at (current_tick - 2)
```

## Key Components

### ClientMain.gd
- **Prediction**: Local player inputs applied immediately
- **Reconciliation**: Position errors fixed by rewinding & replaying
- **Interpolation**: Remote players and enemies smoothly animated between snapshots
- **Static Handling**: Walls get health updates only, no position interpolation
- **Health Handling**: Applied immediately from snapshots (no reconciliation)

### ServerMain.gd
- **Authoritative Simulation**: All entities simulated on server
- **Snapshot Broadcasting**: All entity states sent every tick
- **ACK System**: Per-client acknowledgment with input sequence

### Net.gd
- **Dual Protocol**: ENet (localhost) / WebSocket (cloud)
- **RPC Wrapper**: Unified API for both protocols

### ReplicationManager.gd
- **Entity Registry**: Global net_id → entity mapping
- **Snapshot Building**: Collect all entity states for transmission

## State Categories

### Predicted State (Local Player Only)
- Position
- Rotation
- Velocity

**Why**: Player controls these via input, needs instant feedback

### Non-Predicted State (All Entities)
- Health
- Status effects
- Equipment

**Why**: External factors (damage, pickups), server is source of truth

### Interpolated State (Remote Entities)
- Position
- Rotation
- Velocity
- Health

**Why**: No local input data, must render from server snapshots
**Applies to**: Remote players, enemies (NOT walls)

### Static State (Walls)
- Position (set once on spawn)
- Health (updated from snapshots)

**Why**: Walls don't move after placement, interpolation is wasteful

## Reconciliation Logic

```gdscript
// Only reconcile if POSITION differs
var needs_reconcile = pred_pos.distance_to(srv_pos) >= 5.0

if needs_reconcile:
    1. Rewind to server state
    2. Replay pending inputs
    3. Re-predict future states
```

**Why position only**: 
- Health is authoritative (applied from snapshot)
- Velocity is derived from position
- Reconciling on health causes unnecessary performance hit

## Bullet Prediction Strategy

```
Client shoots:
├─> Spawn predicted bullet (net_id = -1)
├─> Send input to server
└─> Bullet flies immediately (0ms latency)

Server receives input:
├─> Spawn authoritative bullet
├─> Broadcast spawn RPC
└─> Client ignores (already has predicted bullet)

Bullet hits:
├─> Client detects collision (visual)
└─> Server validates & applies damage (authoritative)
```

**Why pure prediction**: 
- Shooting needs instant feedback
- Collision is visual-only on client
- Server validates all damage (prevents cheating)

## Wall Optimization Strategy

```
Client builds wall:
├─> Send build input to server
└─> Server spawns wall, broadcasts to all clients

Client receives wall spawn:
├─> Set position ONCE from spawn data
├─> Add to world (creates physics collision)
└─> Done - wall is now static

Client receives snapshots:
├─> Update wall health from server
├─> Skip interpolation buffer (wall doesn't move)
└─> Skip interpolation loop (no position/rotation changes)
```

**Why static handling**:
- Walls never move after placement
- Interpolating static position is pure waste
- Only health changes (from bullet damage)
- Performance: 30-50% fewer entities in interpolation loop
- Each wall built would add permanent interpolation cost otherwise

## Performance Characteristics

- **Tick Rate**: 60 FPS (16.67ms)
- **Interpolation Delay**: 2 ticks (~33ms)
- **Reconciliation Threshold**: 5 units position error
- **Snapshot Buffer**: 40 snapshots (~666ms history)
- **Pending Input Buffer**: 256 inputs (~4.2s max)

## Network Messages

### Client → Server
- `server_receive_input`: Input command (seq, move, aim, buttons)

### Server → Clients
- `client_receive_snapshot`: All entity states (60/sec)
- `client_receive_ack`: Input acknowledgment per client (60/sec)
- `spawn_entity`: New entity spawned
- `despawn_entity`: Entity removed

## Error Correction

### Position Misprediction
- **Detection**: ACK compares predicted vs server position
- **Correction**: Rewind + replay (full reconciliation)
- **Threshold**: 5 units (prevents jitter from minor errors)

### Health Desync
- **Detection**: Snapshot health differs from local
- **Correction**: Apply server health immediately
- **No Reconciliation**: Position unaffected by health changes

### Packet Loss
- **Snapshots**: Next snapshot contains full state (self-correcting)
- **ACKs**: Old pending inputs eventually replaced
- **Inputs**: Server uses last known input if missing
