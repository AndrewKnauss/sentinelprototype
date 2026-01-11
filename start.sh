#!/bin/bash
chmod +x ./builds/server/SentinelServer.x86_64
./builds/server/SentinelServer.x86_64 --headless -- --server --port=${PORT:-24567}
