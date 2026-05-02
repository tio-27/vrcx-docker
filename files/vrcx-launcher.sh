#!/bin/bash
# /defaults/autostart - Openbox runs this in user X session after init
# Selkies' RESTART_APP=true handles app respawn - keep VRCX foregrounded so it sees exit

set -euo pipefail

# Clear stale Electron Singleton locks from prior crashes
find "${HOME}/.config/VRCX" "${HOME}/.cache/VRCX" \
     -name "Singleton*" -delete 2>/dev/null || true

# --no-sandbox: required for Electron in unprivileged containers
# --disable-gpu: headless container has no GPU
# --no-updater: image rebuild handles version updates
exec /opt/vrcx/vrcx \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --no-updater
