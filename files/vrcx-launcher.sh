#!/bin/sh
# /defaults/autostart - called by svc-de via `sh` (= dash on Ubuntu).
# Mode-agnostic: works under labwc (PIXELFLUX_WAYLAND=true) and Openbox.
# Selkies' RESTART_APP=true (default in this image) handles app respawn.

# Clear stale Electron Singleton locks from prior crashes
find "${HOME}/.config/VRCX" "${HOME}/.cache/VRCX" \
     -name "Singleton*" -delete 2>/dev/null || true

# --no-sandbox: required for Electron in unprivileged containers
# --no-updater: image rebuild handles version updates
# --ozone-platform-hint=auto: enables native Wayland when XDG_SESSION_TYPE=wayland,
#   falls back to X11/Xwayland otherwise. Matches LSIO's docker-obsidian pattern.
#
# Note on --disable-gpu: zero-copy stream encoding works regardless because
# labwc (the compositor) renders on the GPU independently of Electron's
# internal rendering choices. If you hit Electron crashes or rendering
# glitches under Wayland (see electron/electron#50455 - GPU process zygote
# doesn't inherit Wayland flags), uncomment --disable-gpu below as a
# fallback. VRCX will still display correctly, just with software
# compositing inside Electron itself.
exec /opt/vrcx/vrcx \
  --no-sandbox \
  --no-updater \
  --ozone-platform-hint=auto \
  "$@"

# Fallback if Electron crashes under Wayland - replace the exec above with:
#
# exec /opt/vrcx/vrcx \
#   --no-sandbox \
#   --no-updater \
#   --disable-gpu \
#   --disable-software-rasterizer
