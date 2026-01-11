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

### Polish
- ✅ Camera following local player (smooth)
- ✅ Fullscreen scaling (1920x1080)
- ✅ Test session launcher (1 server + 3 clients, quadrant layout)
- ✅ Connection UI (server/port input)

### Deployment
- ✅ Railway.app hosting setup
- ✅ WebSocket server deployed
- ✅ Server running at: web-production-5b732.up.railway.app:443
- ✅ Client connects to cloud server
- ✅ Export configs (Procfile, railway.json, start.sh)

## Latest Session Summary (Jan 2026)
**WebSocket Migration & Cloud Deployment**
- Added USE_WEBSOCKET flag to GameConstants
- Implemented dual protocol support (ENet/WebSocket)
- Created Railway deployment configs
- Deployed server to Railway.app
- Added connection UI to client
- Successfully tested client → cloud server connection
- Ready for HTML5 export to itch.io

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
