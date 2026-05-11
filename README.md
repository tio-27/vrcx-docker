# vrcx-docker

Self-hosted [VRCX](https://github.com/vrcx-team/VRCX) running in a browser via [Selkies WebRTC](https://github.com/selkies-project/selkies) in **Wayland mode** with **Intel QSV/VAAPI zero-copy stream encoding**.

Built fresh from VRCX source on each release tag, packaged on top of `linuxserver/baseimage-selkies:ubuntunoble`. No X server on the host required.

## What this is

VRCX is a Windows/Linux/macOS desktop app for VRChat friend management. This repo wraps the Linux Electron build in a Docker container so you can run it on a NAS or homelab server and access the GUI from any browser.

The container runs in Selkies' Wayland mode using labwc as compositor and pixelflux's Wayland backend for video encoding. With an Intel iGPU passed through, the entire frame pipeline (compositor → encoder → browser) is zero-copy on the GPU. Expect ~5% CPU during active use vs ~25% on the legacy X11/x264enc path.

## Prerequisites

- Docker + Docker Compose
- CPU with **AVX2** support (Intel Haswell or newer / any AMD Ryzen). Older CPUs auto-fallback to X11 mode (no zero-copy)
- Intel iGPU (or AMD GPU) for HW encoding — falls back to CPU encoding if `/dev/dri` not available
- LAN network or reverse proxy (built-in cert is self-signed — use SWAG/Caddy/Traefik for public exposure)
- ~2 GB disk for the image

## Quick start

```bash
mkdir -p /mnt/nvme/docker/vrcx
chown 1000:1000 /mnt/nvme/docker/vrcx

# Check render group GID on host - use that in compose group_add
ls -ln /dev/dri/renderD128

# Save docker-compose.yml from this repo, edit volume path & GID if needed
docker compose pull
docker compose up -d
```

Open `https://<host>:3001` in your browser. Self-signed cert warning is normal — accept once and Chrome remembers it.

> **Note on HTTP vs HTTPS:** Selkies streams via WebRTC, which browsers only allow in [secure contexts](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts). Port 3000 (HTTP) only works from `localhost`. For any remote access (LAN included), use port 3001 (HTTPS), or put the container behind a reverse proxy with proper TLS.

## Hardware acceleration

The image ships with these defaults baked in (Dockerfile `ENV`):

| Variable | Value | Why |
|----------|-------|-----|
| `PIXELFLUX_WAYLAND` | `true` | labwc + pixelflux Wayland backend (zero-copy capable) |
| `NO_GAMEPAD` | `true` | VRCX doesn't need gamepad — saves the userspace gamepad interposer |
| `NO_DECOR` | `true` | No window borders, PWA-style fullscreen |
| `TITLE` | `VRCX` | Browser tab title |

The compose adds:

| Variable | Value | Why |
|----------|-------|-----|
| `DRINODE` | `/dev/dri/renderD128` | Render node for EGL (compositor) |
| `DRI_NODE` | `/dev/dri/renderD128` | Render node for VAAPI/QSV encoding |
| `devices` | `/dev/dri:/dev/dri` | iGPU passthrough |
| `group_add` | `"107"` | Host render group GID — check with `ls -ln /dev/dri/renderD128` |

When `DRINODE` and `DRI_NODE` point to the same device, pixelflux enables its zero-copy path: labwc renders into a GBM buffer on the iGPU, exports it as a dmabuf, and feeds it directly into the libva encoder. No CPU touches the pixel data.

To run without HW acceleration (CPU encoding), comment out `devices`, `group_add`, `DRINODE` and `DRI_NODE` in compose. To force X11 mode entirely, add `PIXELFLUX_WAYLAND=false` to environment.

### Verifying it's working

```bash
# Check VAAPI encode entrypoints inside the container
docker exec -it vrcx vainfo --display drm --device /dev/dri/renderD128 2>&1 | grep VAEntrypointEncSlice

# Confirm Wayland mode is active
docker exec -it vrcx ls /config/.XDG/wayland-1

# CPU usage during an active session
docker stats vrcx --no-stream
```

If `vainfo` shows `VAProfileH264*: VAEntrypointEncSlice` lines, HW encode is loaded. If `wayland-1` exists, you're in Wayland mode. CPU should sit ~5% during active use.

## Configuration

All knobs are environment variables. Image defaults are sane for a LAN homelab on Intel iGPU.

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` / `PGID` | 1000 | User the container runs as — match owner of your `/config` mount |
| `TZ` | Europe/Berlin | Timezone (set in compose) |
| `PIXELFLUX_WAYLAND` | true (in image) | Wayland compositor + zero-copy. Set to `false` to force X11 fallback |
| `DRINODE` / `DRI_NODE` | renderD128 | Render node for rendering / encoding |
| `RESTART_APP` | true | Selkies watchdog auto-restarts VRCX if it crashes |
| `HARDEN_DESKTOP` | true | Single-app lockdown: no sudo, terminals, file transfers |
| `NO_GAMEPAD` | true (in image) | Disable userspace gamepad interposer |
| `NO_DECOR` | true (in image) | No window borders (toggle in UI with Ctrl+Shift+D) |
| `CUSTOM_USER` / `PASSWORD` | unset | Set both to enable HTTP basic auth |
| `SELKIES_MANUAL_WIDTH/HEIGHT` | unset | Lock to fixed resolution and hide the picker (Wayland mode replaces the X11-only `MAX_RES` workaround) |

For the full list see the [baseimage-selkies docs](https://docs.linuxserver.io/images/docker-baseimage-selkies/).

### Auth

LAN-only by default. To enable HTTP basic auth set both `CUSTOM_USER` and `PASSWORD`. For internet exposure put it behind [SWAG](https://github.com/linuxserver/docker-swag) — the built-in auth is described by LSIO themselves as "good enough to keep the kids out, not the internet."

### Persistent data

Everything VRCX writes lives in the `/config` mount:
- `/config/.config/VRCX/` — SQLite database, settings, friend log (back this up)
- `/config/.cache/VRCX/` — Electron cache (disposable)

The SQLite location can be overridden with `VRCX_DatabaseLocation`.

## How the build works

Daily GitHub Actions checks for new VRCX releases:

1. Fetch latest VRCX tag from GitHub API
2. Skip if image already published for that tag (unless `force_rebuild: true`)
3. Build multi-stage Dockerfile:
   - **Stage 1** (`mcr.microsoft.com/dotnet/sdk:9.0`): clone VRCX → `dotnet build` Electron csproj → `npm install` → `npm run prod-linux` (vite) → `download-dotnet-runtime.js` (bundles .NET 9 runtime) → `electron-builder --linux dir`
   - **Stage 2** (`baseimage-selkies:ubuntunoble`): install `chromium` (Electron runtime libs) + `intel-media-va-driver-non-free` (QSV/VAAPI), copy unpacked VRCX, install autostart launcher
4. Push to `ghcr.io/tio-27/vrcx-docker:latest` and `:VRCX_VERSION`

To trigger a manual build: GitHub → Actions → "Build VRCX Docker Image" → Run workflow.

## Troubleshooting

### Black screen or 502 on first load
Container needs ~30s to boot all s6 services. Wait, then refresh.

### `Failed to load cookies: Index was outside the bounds of the array`
[Known upstream VRCX bug](https://github.com/vrcx-team/VRCX/issues/1413), affects Windows builds too. Login still works, the error is harmless.

### Container crash-loops with `s6: svc-de exitcode 137`
Memory limit hit. Bump `deploy.resources.limits.memory` in compose.

### `DRI_NODE not set` or "no such device" in logs
GPU passthrough isn't working. Check `/dev/dri/renderD128` exists on host (`ls -l /dev/dri/`) and the GID in `group_add` matches host render group GID (`ls -ln /dev/dri/renderD128`, third column).

### High CPU usage despite Wayland mode
Confirm `vainfo` shows `VAEntrypointEncSlice`. If not, the iHD driver isn't loading — check that the host kernel exposes `/dev/dri/renderD128` and the container has access. Common causes: missing render group, `DRINODE` and `DRI_NODE` pointing to different devices (forces readback fallback).

### VRCX crashes or shows rendering glitches
Known Electron-Wayland issue ([electron/electron#50455](https://github.com/electron/electron/issues/50455)) — the GPU process zygote doesn't always inherit Wayland flags correctly. Workaround: edit `files/vrcx-launcher.sh` and uncomment the `--disable-gpu` lines. Stream encoding stays zero-copy (labwc renders independently); only Electron's internal rendering falls back to software.

### Wayland mode falls back to X11
Your CPU lacks AVX2. The Wayland stack requires Intel Haswell or newer / any AMD Ryzen. Atom-based and some low-end Celerons won't work and will silently fall back.

### Different VRCX version needed
Trigger workflow with `vrcx_version: v2026.01.28` (or whatever tag), then `docker compose pull && docker compose up -d`.

## License

MIT — see [LICENSE](LICENSE). VRCX itself is also MIT-licensed by the [VRCX team](https://github.com/vrcx-team/VRCX).

This project is not affiliated with VRCX, VRChat, Selkies, or LinuxServer.io.
