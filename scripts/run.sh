#!/usr/bin/env bash
# Rebuilds the app, quits any running copy and opens the new one.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x cLockIn 2>/dev/null || true
sleep 0.5
open build/cLockIn.app
