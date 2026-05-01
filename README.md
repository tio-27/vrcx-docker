# vrcx-docker

VRCX in einem Docker-Container, basierend auf **linuxserver/webtop** (Selkies/WebRTC).
Build from source via GitHub Actions, täglich auf neue VRCX-Releases geprüft.

---

## Architektur

- **Multi-Stage Build:** dotnet-SDK-Container baut VRCX, Webtop-Image bekommt nur die fertigen Files
- **Base-Image:** `lscr.io/linuxserver/webtop:ubuntu-xfce` mit Selkies (WebRTC statt KasmVNC-WebSocket — VRCX/Electron läuft damit zuverlässiger)
- **HTTP statt HTTPS:** Port 3000, kein Cert-Self-Signed-Theater mehr
- **Keine Auth-Pflicht:** `PASSWORD` ENV nicht gesetzt = direkter Zugriff (LAN-only)
- **VRCX-Autostart:** XFCE startet VRCX über `~/.config/autostart/vrcx.desktop` mit eigenem Watchdog
- **Watchdog:** Lock-Cleanup vor jedem Start + Process-Tree-Wait gegen den Electron-Self-Relaunch-Loop
- **GHCR-Tag-Check:** Workflow fragt direkt das GHCR-Manifest ab statt Git-State-Tracking
- **Persistent Volume:** `/config` (statt `/home/kasm-user/.config/VRCX` wie bei Kasm)

---

## Setup

### 1. GitHub-Repo anlegen

GitHub → New repository → `vrcx-docker` (public empfohlen).

### 2. Dateien hochladen (Git CLI)

```bash
cd ~/Downloads/vrcx-docker
git init && git branch -M main
git add . && git commit -m "init"
git remote add origin https://github.com/DEIN_USERNAME/vrcx-docker.git
git push -u origin main
```

GitHub fragt nach Username + **Personal Access Token** (Settings → Developer settings → Tokens classic, Scope `repo`).

### 3. Actions-Permissions

Repo → Settings → Actions → General → Workflow permissions → **Read and write permissions** → Save.

### 4. Ersten Build triggern

Repo → Actions → Build VRCX Docker Image → Run workflow → `force_rebuild: true`.
Buildzeit: 15–25 Minuten.

### 5. Image visibility

Profile → Packages → vrcx-docker → Package settings → Public.

### 6. Deployment

Volume vorbereiten:
```bash
mkdir -p /mnt/nvme/docker/vrcx
chown 1000:1000 /mnt/nvme/docker/vrcx
```

`docker-compose.yml` anpassen — `YOUR_GITHUB_USERNAME` durch lowercase Username ersetzen.

```bash
docker compose up -d
```

VRCX erreichbar unter: `http://TRUENAS_IP:3000` (HTTP, kein Cert).
**Keine Anmeldung nötig** — kommt direkt auf den Desktop, VRCX startet automatisch.

---

## Konfiguration

### Environment Variables

| ENV | Default | Zweck |
|-----|---------|-------|
| `PUID` | `1000` | User-ID für File-Ownership |
| `PGID` | `1000` | Group-ID |
| `TZ` | `Etc/UTC` | Timezone |
| `TITLE` | `Selkies` | Browser-Tab-Titel |
| `CUSTOM_USER` | `abc` | HTTP-Basic-Auth User (nur wenn PASSWORD gesetzt) |
| `PASSWORD` | unset | HTTP-Basic-Auth Password — **wenn unset, keine Auth!** |
| `SELKIES_MANUAL_WIDTH` | unset | Lock auf feste Breite (sonst dynamisch nach Browser-Größe) |
| `SELKIES_MANUAL_HEIGHT` | unset | Lock auf feste Höhe |

### Volume

| Pfad im Container | Inhalt |
|---|---|
| `/config` | XFCE-Profile, VRCX-Settings, SQLite-DB, Logs — alles persistent |

VRChat-Login-Token bleibt persistent über Updates und Restarts.

---

## Updates

Workflow läuft täglich 06:00 UTC, prüft via GitHub API auf neue VRCX-Releases.

Auf TrueNAS:
```bash
docker compose pull && docker compose up -d
```

Force-Rebuild manuell: Actions → Run workflow → `force_rebuild: true`.

---

## Bekannte Einschränkungen

- **Memory Leak** (VRCX Issue #1647): Watchdog im Launcher restartet bei Crash
- `--disable-gpu` ist gesetzt — kein Hardware-Rendering
- `shm_size: 1gb` Pflicht für Chromium/Electron
- Kein VR-Overlay, läuft headless
- `--no-updater` verhindert In-App-Updates (Updates kommen über GHCR-Pull)

---

## Troubleshooting

**`docker pull` failed mit "denied":**
Image private. Public machen oder lokal authentifizieren:
```bash
echo "DEIN_PAT" | docker login ghcr.io -u DEIN_USERNAME --password-stdin
```

**VRCX startet nicht / crasht im Loop:**
```bash
docker exec -it vrcx bash
cat /config/.config/VRCX/launcher.log
ps aux | grep vrcx
```

**Browser zeigt nichts unter `http://IP:3000`:**
- HTTP statt HTTPS verwenden
- Port 3000 (nicht 6901)
- Falls Authentifizierung kommt: `PASSWORD` ist gesetzt im Compose, oder leer lassen

**Resolution ist zu klein:**
Browser-Fenster maximieren — Selkies skaliert dynamisch mit. Für feste Auflösung: `SELKIES_MANUAL_WIDTH=1920` und `SELKIES_MANUAL_HEIGHT=1080` als ENV setzen.

**Workflow läuft nicht:**
Schedules pausieren bei niedriger Repo-Aktivität nach 60 Tagen — manueller Trigger reaktiviert.

---

## Quellen

- VRCX Build-from-source: https://github.com/vrcx-team/VRCX/wiki/Building-from-source
- linuxserver/webtop: https://github.com/linuxserver/docker-webtop
- linuxserver baseimage-selkies: https://github.com/linuxserver/docker-baseimage-selkies
- Selkies framework: https://github.com/selkies-project
- VRCX Memory Leak: https://github.com/vrcx-team/VRCX/issues/1647
