#!/bin/bash
# Watchdog: starts VRCX, restarts on crash/OOM
set -u

VRCX_FLAGS=(
  --no-sandbox
  --disable-gpu
  --disable-software-rasterizer
  --disable-dev-shm-usage
  --no-updater
)

/usr/bin/desktop_ready

(
  while true; do
    /opt/vrcx/vrcx "${VRCX_FLAGS[@]}" >> /tmp/vrcx.log 2>&1
    EXIT_CODE=$?
    echo "[$(date -Iseconds)] VRCX exited with code $EXIT_CODE, restarting in 5s..." >> /tmp/vrcx.log
    sleep 5
  done
) &
