# vrcx-docker

Self-hosted [VRCX](https://github.com/vrcx-team/VRCX) running in a browser via [Selkies WebRTC](https://github.com/selkies-project/selkies).

Built fresh from VRCX source on each release tag, packaged on top of `linuxserver/baseimage-selkies:ubuntunoble` for single-app browser access. No X server on the host required.

## What this is

VRCX is a Windows/Linux/macOS desktop app for VRChat friend management. This repo wraps the Linux Electron build in a Docker container so you can run it on a NAS or homelab server and access the GUI from any browser. Useful if you don't have a Windows desktop running 24/7 or want to keep VRCX state separate from your gaming machine.

## Prerequisites

- Docker + Docker Compose
- LAN network or reverse proxy (no built-in HTTPS - use SWAG/Caddy/Traefik for public exposure)
- ~2 GB disk for the image, plus your `/config` volume

## Quick start

```bash
mkdir -p /mnt/nvme/docker/vrcx
chown 1000:1000 /mnt/nvme/docker/vrcx

# Save docker-compose.yml from this repo, edit volume path if needed
docker compose pull
docker compose up -d
```

Open `http://<host>:3000` in your browser. VRCX launches in fullscreen Openbox.

## Configuration

All knobs are environment variables in `docker-compose.yml`. The defaults are tuned for a LAN homelab.

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` / `PGID` | 1000 | User the container runs as - match owner of your `/config` mount |
| `TZ` | Europe/Berlin | Timezone |
| `RESTART_APP` | true | Selkies watchdog auto-restarts VRCX if it crashes |
| `HARDEN_DESKTOP` | true | Single-app lockdown: no sudo, terminals, file transfers |
| `MAX_RES` | 1920x1080 | Caps virtual display from default 16k - saves RAM |
| `NO_DECOR` | true | Removes window borders for PWA-like fullscreen |
| `CUSTOM_USER` / `PASSWORD` | unset | Set both to enable HTTP basic auth (see below) |
| `SELKIES_MANUAL_WIDTH/HEIGHT` | unset | Lock to fixed resolution (uncomment in compose) |

For the full list see the [baseimage-selkies docs](https://docs.linuxserver.io/images/docker-baseimage-selkies/).

### Auth

LAN-only by default. To enable HTTP basic auth set both `CUSTOM_USER` and `PASSWORD`. For internet exposure put it behind [SWAG](https://github.com/linuxserver/docker-swag) - the built-in auth is described by LSIO themselves as "good enough to keep the kids out, not the internet."

### Persistent data

Everything VRCX writes lives in the `/config` mount:
- `/config/.config/VRCX/` - SQLite database, settings, friend log (back this up)
- `/config/.cache/VRCX/` - Electron cache (disposable)

The SQLite location can be overridden with `VRCX_DatabaseLocation` if you want it on different storage.

## How the build works

The repo is just a Dockerfile + Selkies-compatible launcher. Daily GitHub Actions checks for new VRCX releases:

1. Fetch latest VRCX tag from GitHub API
2. Skip if image already published for that tag (unless `force_rebuild: true`)
3. Build multi-stage Dockerfile:
   - **Stage 1** (`mcr.microsoft.com/dotnet/sdk:9.0`): clone VRCX → `dotnet build` Electron csproj → `npm ci` → `npm run prod-linux` (vite) → `download-dotnet-runtime.js` (bundles .NET 9 runtime) → `electron-builder --linux dir`
   - **Stage 2** (`baseimage-selkies:ubuntunoble`): install runtime libs + system .NET 9 fallback, copy unpacked VRCX, install autostart launcher
4. Push to `ghcr.io/tio-27/vrcx-docker:latest` and `:VRCX_VERSION`

To trigger a manual build: GitHub → Actions → "Build VRCX Docker Image" → Run workflow. Optionally pin a specific VRCX version.

## Troubleshooting

### Black screen or 502 on first load
Container needs ~30s to boot all s6 services. Wait, then refresh.

### `Failed to load cookies: Index was outside the bounds of the array`
[Known upstream VRCX bug](https://github.com/vrcx-team/VRCX/issues/1413), affects Windows builds too. Login still works, the error is harmless.

### `duplicate column name: group_name` followed by `no such column: groupName`
Upstream SQLite migration bug in VRCX, not container-related. Login still works after this error fires once.

### Container crash-loops with `s6: svc-de exitcode 137`
You're hitting the 4GB memory limit. Bump `deploy.resources.limits.memory` in compose, or check if your host is OOM-killing the container.

### Login button does nothing
Open browser DevTools, check console. If you see CORS or websocket errors, the issue is usually a misconfigured reverse proxy. The container itself uses plain HTTP on port 3000.

### Different VRCX version needed
Trigger workflow with `vrcx_version: v2026.01.28` (or whatever tag), then `docker compose pull && docker compose up -d`.

## License

MIT - see [LICENSE](LICENSE). VRCX itself is also MIT-licensed by the [VRCX team](https://github.com/vrcx-team/VRCX).

This project is not affiliated with VRCX, VRChat, Selkies, or LinuxServer.io.
