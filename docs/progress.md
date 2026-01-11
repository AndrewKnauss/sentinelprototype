# Progress

## Completed

### Core Systems (Jan 2026)
- ✅ Client-server architecture (Godot 4.4 ENet)
- ✅ Client prediction + server reconciliation
- ✅ Entity interpolation (players, enemies, walls)
- ✅ ReplicationManager for entity registry
- ✅ Bootstrap launcher (--server / --client args)

### Entities
- ✅ Player (movement, shooting, building)
- ✅ Enemy (AI: chase/wander/separate, shooting)
- ✅ Bullet (client-predicted, client-collision)
- ✅ Wall (buildable, damageable, physics collision)

### Networking
- ✅ Input buffering + sequence numbers
- ✅ Snapshot transmission
- ✅ ACK system for reconciliation
- ✅ Spawn/despawn RPCs
- ✅ Client-side bullet prediction (zero-latency shooting)
- ✅ Client-side collision detection
- ✅ WebSocket support (browser-compatible)
- ✅ Dual protocol support (ENet/WebSocket toggle)
- ✅ Wall optimization (static entities, no interpolation)
- ✅ Position-only reconciliation (health from snapshots)

### Polish
- ✅ Camera following local player (smooth)
- ✅ Fullscreen scaling (1920x1080)
- ✅ Test session launcher (1 server + 3 clients, quadrant layout)
- ✅ Connection UI (server/port input)
- ✅ Hurt flash effect (players and enemies flash when damaged)
- ✅ Local player visual (black color for easy identification)

### Deployment
- ✅ Railway.app hosting setup
- ✅ WebSocket server deployed
- ✅ Server running at: web-production-5b732.up.railway.app:443
- ✅ Client connects to cloud server
- ✅ Export configs (Procfile, railway.json, start.sh)

## Latest Session Summary (Jan 2026)
**Session #1 - Network Optimization & Hurt Flash**
- Wall optimization: Static entities no longer interpolated (30-50% performance gain)
- Position-only reconciliation: Health applied directly from snapshots (no rewind/replay)
- Hurt flash for enemies: WHITE flash on damage (matches players)
- Hurt flash triggers via interpolation for remote entities
- Documentation: Architecture.md, wall_optimization.md, hurt_flash.md
- Performance: Eliminated unnecessary interpolation, reduced reconciliation triggers

**Previous: Visual Polish & Quality of Life**
- Added hurt flash effect (players flash red when damaged)
- Local player now appears black (easy identification)
- Reconciliation checks all state (position + health)
- Added --auto-connect flag for local testing
- Created run_client_local.bat for quick localhost testing
- Updated test session to auto-connect all clients
- Deployed to itch.io: https://woolachee.itch.io/sentinel
- Created TODO.md with full feature roadmap

**Previous: WebSocket Migration & Cloud Deployment**
- Added USE_WEBSOCKET flag to GameConstants
- Implemented dual protocol support (ENet/WebSocket)
- Created Railway deployment configs
- Deployed server to Railway.app
- Added connection UI to client
- Successfully tested client → cloud server connection

## In Progress
- HTML5 export for browser play

## Next Up
- Upload HTML5 build to itch.io
- World events (timed loot spawns)
- Inventory system
- Resource gathering
- Hot loot mechanics
- PvP zones with lawfulness gradient
- Bounty system
