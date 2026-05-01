#!/bin/bash
# Webtop autostart launcher (placed at /defaults/autostart)
# Webtop runs this on container start. It must wait for the display server
# to be ready, then keep VRCX alive with a watchdog loop.

set -u

VRCX_FLAGS=(
  --no-sandbox
  --disable-gpu
  --disable-software-rasterizer
  --disable-dev-shm-usage
  --no-updater
)

LOG_FILE="${HOME}/.config/VRCX/launcher.log"
mkdir -p "$(dirname "$LOG_FILE")"

cleanup_locks() {
  find "${HOME}/.config/VRCX" "${HOME}/.cache/VRCX" \
       -name "Singleton*" -delete 2>/dev/null || true
}

wait_for_vrcx_gone() {
  while pgrep -f "/opt/vrcx/vrcx" > /dev/null 2>&1; do
    sleep 2
  done
}

# Wait for display server (Selkies/X11)
for i in $(seq 1 60); do
  if [ -n "${DISPLAY:-}" ] && xset q >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

while true; do
  cleanup_locks

  /opt/vrcx/vrcx "${VRCX_FLAGS[@]}" >> "$LOG_FILE" 2>&1 &
  INITIAL_PID=$!

  wait $INITIAL_PID 2>/dev/null
  EXIT_CODE=$?

  sleep 3
  wait_for_vrcx_gone

  echo "[$(date -Iseconds)] VRCX exited (code $EXIT_CODE), restarting in 5s..." >> "$LOG_FILE"
  sleep 5
done