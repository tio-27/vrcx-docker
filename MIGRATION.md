# Migration: X11 → Wayland + QSV/VAAPI

Anleitung zum Umstieg vom alten X11/Software-Encoding-Setup auf den neuen Wayland-Mode mit Intel HW-Encoding.

## Was sich geändert hat

| | Alt (X11) | Neu (Wayland) |
|---|---|---|
| Compositor | Openbox | labwc |
| Stream-Encoder | x264enc auf CPU | VAAPI auf iGPU (zero-copy) |
| CPU-Last (aktive Session) | ~20–30 % | ~5 % |
| Pipeline | Xvfb → XShm → CPU → libx264 | labwc → GBM → dmabuf → libva |
| GPU im Launcher | `--disable-gpu` aktiv | aktiviert (mit Fallback-Option) |
| Auflösungs-Cap | `MAX_RES=1920x1080` | nicht nötig, ggf. `SELKIES_MANUAL_WIDTH/HEIGHT` |
| Electron-Runtime-Libs | manuell kuratierte Liste | `chromium` Meta-Package |
| Image-Defaults | sparsam | `PIXELFLUX_WAYLAND/NO_GAMEPAD/NO_DECOR` als ENV |

**Hinweis zu `MAX_RES`:** Im X11-Mode war das ein Workaround für die 16K-Pixelplane von Xvfb (CPU-Readback wurde sonst absurd teuer). Im Wayland-Mode ist das obsolet — Smithay handelt die Auflösung dynamisch. Wenn du die Auflösung trotzdem auf einen festen Wert klemmen willst (z.B. für PWA-Nutzung), nutze `SELKIES_MANUAL_WIDTH` und `SELKIES_MANUAL_HEIGHT`.

Pixelflux X11-Backend ist explizit Legacy. Das Wayland-Backend (Smithay/Rust) ist der aktive Pfad bei LSIO und der einzige, der HW-Encoding auf Intel/AMD unterstützt.

## Voraussetzungen am Host (TrueNAS)

1. CPU mit AVX2 (Intel Haswell+ oder Ryzen). Pentium Gold 8505 (Alder Lake-N) hat AVX2 ✓
2. iGPU verfügbar:
   ```bash
   ls -l /dev/dri/
   # erwartet: card0, renderD128
   ```
3. Render-Group-GID checken (kommt in den Container per `group_add`):
   ```bash
   ls -ln /dev/dri/renderD128
   # 3. Spalte ist die GID, z.B. 107 auf TrueNAS Scale
   ```
4. Die GID in `docker-compose.yml` unter `group_add` setzen, falls sie nicht 107 ist.

## Migration durchführen

Die Daten unter `/mnt/nvme/docker/vrcx/.config/VRCX/` (SQLite-DB, Cookies, Friend-Logs) bleiben erhalten — es wird nur das Image getauscht und der Compositor umgestellt.

```bash
cd /pfad/zu/vrcx-compose

# Compose-File aus dem neuen Repo übernehmen.
# Das Image bringt PIXELFLUX_WAYLAND/NO_GAMEPAD/NO_DECOR als Defaults mit -
# du musst nur DRINODE/DRI_NODE und group_add setzen.

docker compose down
docker compose pull
docker compose up -d

# Logs anschauen — beim ersten Start ~30s warten
docker compose logs -f vrcx
```

In den Logs solltest du diese Zeilen sehen, die den Wayland-Mode bestätigen:

```
[svc-de] Wayland mode: Waiting for socket at /config/.XDG/wayland-1...
[svc-de] /config/.XDG/wayland-1 found launching de
```

## Verifizieren dass HW-Encoding läuft

```bash
# iHD-Treiber lädt und kann encoden
docker exec -it vrcx vainfo --display drm --device /dev/dri/renderD128 \
  | grep -E "VAProfileH264|VAEntrypointEncSlice"
# erwartet: mehrere VAProfileH264*  : VAEntrypointEncSlice  Zeilen

# Wayland-Socket existiert
docker exec -it vrcx ls -la /config/.XDG/

# CPU-Last während aktiver Browser-Session messen
docker stats vrcx --no-stream
# erwartet: ~5% statt vorher ~25%
```

Wenn `vainfo` keine `VAEntrypointEncSlice`-Zeilen zeigt, ist der Treiber nicht aktiv. Häufige Ursachen:
- Render-Group-GID stimmt nicht
- `/dev/dri` ist nicht durchgereicht
- DRINODE != DRI_NODE → Readback-Fallback

## Rollback

Falls was nicht klappt — alter Mode geht jederzeit:

```yaml
environment:
  - PIXELFLUX_WAYLAND=false
  # DRINODE und DRI_NODE können drin bleiben, werden in X11 ignoriert
```

Daten bleiben unangetastet, Container startet wieder mit Openbox + CPU-Encoding.

## Bekannte Einschränkungen

- **Clipboard X11↔Wayland-Sync ist im Hybrid-Mode unvollständig** (Issue [#136](https://github.com/linuxserver/docker-baseimage-selkies/issues/136)). Browser↔Wayland funktioniert, X11-Apps innerhalb der Session nicht durchgängig.
- **Electron #50455**: GPU-Process-Zygote vererbt Wayland-Flags nicht zuverlässig, kann zu erhöhter Electron-internen CPU-Last führen. Stream-Encoding bleibt davon unberührt. Falls VRCX visuell glitcht oder crasht, `--disable-gpu` im Launcher aktivieren (siehe Kommentar in `files/vrcx-launcher.sh`).
- **AVX2-Pflicht**: ohne AVX2 fällt der Wayland-Mode automatisch auf X11 zurück. Im X11-Mode gibt es kein zero-copy mehr (LSIO hat HW-Acceleration für X11 deprecated).

## Was bleibt gleich

- Image-Repo und Tag (`ghcr.io/tio-27/vrcx-docker:latest`)
- Persistenz-Pfad (`/mnt/nvme/docker/vrcx`)
- Ports (3000 HTTP, 3001 HTTPS)
- Auth-Mechanismus (`CUSTOM_USER` / `PASSWORD`)
- VRCX selbst — keine User-sichtbaren Änderungen

Migrations-Aufwand: Compose-File austauschen, einmal `docker compose up -d --force-recreate`, fertig.
