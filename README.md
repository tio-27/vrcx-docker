# vrcx-docker

VRCX als Single-Application Docker-Container, basierend auf **`linuxserver/baseimage-selkies`** (Selkies/WebRTC).
Build from source via GitHub Actions, täglich auf neue VRCX-Releases geprüft.

## Architektur

- **Multi-Stage Build:** dotnet-SDK-Container baut VRCX, Selkies-Image bekommt nur die fertigen Binaries
- **Base-Image:** `ghcr.io/linuxserver/baseimage-selkies:ubuntunoble` mit Openbox als minimaler Window Manager
- **Single-Application Mode:** kein XFCE, kein Multi-Session-Quark — Openbox rendert nur VRCX im Vollbild
- **WebRTC statt VNC:** Selkies-Streaming, Login-Probleme aus KasmVNC umgangen
- **HTTP statt HTTPS:** Port 3000, kein Cert-Theater
- **Keine Auth:** `PASSWORD` ENV nicht gesetzt = direkter Zugriff (LAN)
- **`/defaults/autostart`:** Webtop-Konvention für Single-App-Launcher mit Watchdog
- **GHCR-Tag-Check:** Workflow fragt direkt das GHCR-Manifest ab

## Setup

### 1. GitHub-Repo

`vrcx-docker` als public repo anlegen (Actions unlimited bei Public).

### 2. Files hochladen

```bash
cd ~/Downloads/vrcx-docker
git init && git branch -M main
git add . && git commit -m "init"
git remote add origin https://github.com/DEIN_USERNAME/vrcx-docker.git
git push -u origin main
```

### 3. Actions-Permissions

Repo → Settings → Actions → General → Workflow permissions → **Read and write** → Save.

### 4. Build triggern

Repo → Actions → Build VRCX Docker Image → Run workflow → `force_rebuild: true`.
Buildzeit: 15–25 min.

### 5. Image public machen

Profile → Packages → vrcx-docker → Package settings → Public.

### 6. TrueNAS Deployment

```bash
mkdir -p /mnt/nvme/docker/vrcx
chown 1000:1000 /mnt/nvme/docker/vrcx
```

`docker-compose.yml` anpassen — `YOUR_GITHUB_USERNAME` durch deinen lowercase Username ersetzen.

```bash
docker compose up -d
```

VRCX im Browser: `http://TRUENAS_IP:3000`. Keine Anmeldung — kommt direkt zu VRCX.

## Konfiguration

### Environment Variables

| ENV | Default | Zweck |
|-----|---------|-------|
| `PUID` | `1000` | User-ID |
| `PGID` | `1000` | Group-ID |
| `TZ` | `Etc/UTC` | Timezone |
| `TITLE` | `Selkies` | Browser-Tab-Titel |
| `NO_DECOR` | `true` | Fenster-Dekorationen aus (PWA-Style) |
| `CUSTOM_USER` | `abc` | Auth-User (nur wenn PASSWORD gesetzt) |
| `PASSWORD` | unset | Auth-Password — wenn unset = keine Auth |
| `SELKIES_MANUAL_WIDTH` | unset | Feste Breite (sonst dynamisch) |
| `SELKIES_MANUAL_HEIGHT` | unset | Feste Höhe |
| `MAX_RES` | `15360x8640` | Max-Resolution für Xvfb |

### Volume

| Pfad | Inhalt |
|---|---|
| `/config` | Home-Dir des `abc` Users — VRCX-DB, Settings, Logs persistent |

VRChat-Login bleibt persistent über Updates und Restarts.

## Updates

Workflow läuft täglich 06:00 UTC. Neue VRCX-Releases werden automatisch gebaut.

```bash
docker compose pull && docker compose up -d
```

Force-Rebuild: Actions → Run workflow → `force_rebuild: true`.
Spezifische Version: `vrcx_version: v2026.01.28`.

## Bekannte Einschränkungen

- **Memory Leak** (VRCX Issue #1647): Watchdog im Launcher restartet bei Crash
- `--disable-gpu` — kein Hardware-Rendering
- `shm_size: 1gb` Pflicht für Chromium/Electron
- Headless, kein VR-Overlay
- `--no-updater` — In-App-Updates aus, Updates über GHCR-Pull

## Troubleshooting

**Image pull failed mit "denied":**
Image private. Public machen oder lokal authentifizieren:
```bash
echo "DEIN_PAT" | docker login ghcr.io -u DEIN_USERNAME --password-stdin
```

**VRCX startet nicht oder crasht:**
```bash
docker exec -it vrcx bash
cat /config/.config/VRCX/launcher.log
ps aux | grep vrcx
```

**Login-Button reagiert nicht:**
Volume frisch:
```bash
docker compose down
rm -rf /mnt/nvme/docker/vrcx/*
chown 1000:1000 /mnt/nvme/docker/vrcx
docker compose up -d
```

**Auflösung schlecht:**
Browser-Fenster größer ziehen — Selkies skaliert dynamisch. Für feste Auflösung:
```yaml
- SELKIES_MANUAL_WIDTH=1920
- SELKIES_MANUAL_HEIGHT=1080
```

## Quellen

- VRCX Build-from-source: https://github.com/vrcx-team/VRCX/wiki/Building-from-source
- baseimage-selkies: https://github.com/linuxserver/docker-baseimage-selkies
- Selkies Project: https://github.com/selkies-project
- VRCX Memory Leak: https://github.com/vrcx-team/VRCX/issues/1647
