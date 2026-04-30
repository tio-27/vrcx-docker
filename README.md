# vrcx-docker

VRCX in einem Docker-Container auf Basis von `kasmweb/core-ubuntu-jammy:1.18.0`.
Build from source via GitHub Actions, täglich auf neue VRCX-Releases geprüft.

---

## Architektur

- **Multi-Stage Build:** dotnet-SDK-Container baut VRCX (dotnet → npm install → prod-linux → electron-builder --dir), Kasm-Image bekommt nur die fertige `linux-unpacked` Tree. Final-Image bleibt schlank.
- **Build-Reihenfolge** strikt nach offizieller VRCX-Wiki: dotnet ZUERST, dann `npm install`, `npm run prod-linux`, dann electron-builder.
- **electron-builder `--dir` Target:** statt AppImage → entpackter Ordner direkt. Vermeidet das FUSE-in-Docker-Problem komplett.
- **Kasm-Konvention** vollständig eingehalten: `STARTUPDIR`, `kasm-default-profile`, `set_user_permission.sh`, finaler `USER 1000`. Customizations zwischen den `######### Customize Container Here ###########` Markers.
- **Watchdog-Loop** im custom_startup: VRCX wird bei Crash/OOM automatisch neugestartet (Workaround für den bekannten Memory-Leak Issue #1647).
- **GHCR-Tag-Check** statt Git-State-File: Workflow fragt direkt GHCR-Manifest ab, ob der Tag schon existiert.

---

## Voraussetzungen

- GitHub-Repo
- GitHub Actions aktiviert
- GHCR ist automatisch verfügbar

---

## Setup

### 1. Repo anlegen und pushen

```bash
git init vrcx-docker && cd vrcx-docker
# Alle Dateien aus diesem Bundle reinkopieren (inkl. files/ und .github/)
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/vrcx-docker.git
git push -u origin main
```

### 2. `docker-compose.yml` anpassen

`YOUR_GITHUB_USERNAME` ersetzen (lowercase!), GHCR-URLs sind case-sensitive:

```yaml
image: ghcr.io/your_username/vrcx-docker:latest
```

`VNC_PW` und `TZ` nach Bedarf ändern.

### 3. Repo Settings → Actions → Workflow permissions

Auf **"Read and write permissions"** setzen, sonst kann der Workflow nichts nach GHCR pushen.

### 4. Ersten Build triggern

GitHub → Actions → `Build VRCX Docker Image` → `Run workflow` → `force_rebuild: true`.

Buildzeit: ~15–20 Minuten. Free-Runner haben 7 GB RAM und 14 GB Disk – der Workflow räumt vorher Disk frei.

### 5. Image öffentlich machen (optional)

Default ist private. Für `docker pull` ohne Auth:
GitHub → Profile → Packages → `vrcx-docker` → Package settings → Change visibility → Public.

### 6. Deployment

```bash
docker compose up -d
```

VRCX erreichbar unter: `https://HOST_IP:6901` (Kasm nutzt self-signed HTTPS).
Login: User `kasm_user`, Password aus `VNC_PW`.

---

## Automatische Updates

Der Workflow läuft täglich um 06:00 UTC.

Logik:
1. Holt latest VRCX-Release via GitHub API
2. Fragt GHCR-Manifest für diesen Tag ab
3. Existiert der Tag schon → skip. Sonst → Build mit `VRCX_REF=<tag>`

Manueller Force-Rebuild: Actions → `Run workflow` → `force_rebuild: true`.

---

## Konfiguration

| ENV | Default | Zweck |
|-----|---------|-------|
| `VNC_PW` | `password` | Web-UI Login |
| `TZ` | `UTC` | Container-Timezone |

| Volume | Pfad | Inhalt |
|--------|------|--------|
| `vrcx-config` | `/home/kasm-user/.config/VRCX` | SQLite-DB, Settings, Logs |

---

## Bekannte Einschränkungen

- **Memory Leak** (VRCX Issue #1647): Watchdog im startup script restartet bei Crash. SQLite-DB bleibt erhalten.
- `--disable-gpu` ist gesetzt – kein Hardware-Rendering, sonst Crash-Loop laut Issue #1647.
- `shm_size: 1gb` ist Pflicht für Chromium/Electron, sonst Renderer-Crashes.
- **Kein VR-Overlay**, kein OpenVR-Support – läuft headless.
- **Kein Auto-Update In-App**: `--no-updater` Flag verhindert dass VRCX sich selbst überschreibt. Updates kommen über neue Image-Builds.

---

## Troubleshooting

**Build schlägt fehl mit "linux-unpacked dir not found":**
electron-builder hat den Output nicht erstellt. Logs in der Action prüfen, meist liegt's an einem npm-Build-Error oder fehlenden dotnet-Artifacts.

**Container startet, VRCX nicht sichtbar:**
SSH ins Container: `docker exec -it vrcx bash`, dann `cat /tmp/vrcx.log`.

**OOMKilled-Loop:**
Kein Memory-Limit setzen oder mindestens 4 GB. VRCX selbst läuft mit ~500 MB-1 GB, plus Chromium overhead.

**GHCR pull failed: "denied":**
Image ist private. Entweder public machen (siehe Setup 5) oder lokal: `docker login ghcr.io -u USERNAME -p $(gh auth token)`.

---

## Quellen

- VRCX Build-from-source Wiki: https://github.com/vrcx-team/VRCX/wiki/Building-from-source
- Kasm Custom Image Doku: https://docs.kasm.com/docs/how-to/building_images/
- VRCX Memory Leak Issue: https://github.com/vrcx-team/VRCX/issues/1647
- electron-builder Linux Targets: https://www.electron.build/linux
