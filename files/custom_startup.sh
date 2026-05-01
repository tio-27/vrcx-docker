#!/bin/bash
# Watchdog for VRCX
# - Cleans up stale singleton locks before each launch
# - Waits for the FULL VRCX process tree to exit before restarting
#   (Electron self-relaunches on startup; without this the watchdog
#    would race the relaunched process and cause a "Another instance
#    is already running" loop)

set -u

VRCX_FLAGS=(
  --no-sandbox
  --disable-gpu
  --disable-software-rasterizer
  --disable-dev-shm-usage
  --no-updater
)

cleanup_locks() {
  find /home/kasm-user/.config/VRCX /home/kasm-user/.cache/VRCX \
       -name "Singleton*" -delete 2>/dev/null || true
}

wait_for_all_vrcx_gone() {
  while pgrep -f "/opt/vrcx/vrcx" > /dev/null 2>&1; do
    sleep 2
  done
}

/usr/bin/desktop_ready

(
  while true; do
    cleanup_locks

    /opt/vrcx/vrcx "${VRCX_FLAGS[@]}" >> /tmp/vrcx.log 2>&1 &
    INITIAL_PID=$!

    wait $INITIAL_PID 2>/dev/null
    EXIT_CODE=$?

    sleep 3
    wait_for_all_vrcx_gone

    echo "[$(date -Iseconds)] All VRCX processes exited (initial code $EXIT_CODE), restarting in 5s..." >> /tmp/vrcx.log
    sleep 5
  done
) &
