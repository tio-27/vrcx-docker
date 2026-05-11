# syntax=docker/dockerfile:1

# ---------- Stage 1: Build VRCX from source ----------
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder

ARG VRCX_REF=master

# Build deps - electron-builder needs these for native rebuild stages
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates \
        libgbm1 libnss3 libasound2 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libdrm2 libxcomposite1 libxdamage1 libxfixes3 \
        libxkbcommon0 libxrandr2 libxshmfence1 libnspr4 libdbus-1-3 \
        libexpat1 libxcb1 libx11-6 libxext6 libxtst6 libxi6 \
        libpangocairo-1.0-0 libgtk-3-0 \
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Shallow clone the requested ref - tag or branch
RUN git clone --depth 1 --branch "${VRCX_REF}" https://github.com/vrcx-team/VRCX.git . \
    || (git clone https://github.com/vrcx-team/VRCX.git . && git checkout "${VRCX_REF}")

# 1. Build .NET 9 Electron-side assembly
RUN --mount=type=cache,target=/root/.nuget/packages,sharing=locked \
    dotnet build 'Dotnet/VRCX-Electron.csproj' \
        -p:Configuration=Release \
        -p:WarningLevel=0 \
        -p:Platform=x64 \
        -p:PlatformTarget=x64 \
        -p:RestorePackagesConfig=true \
        -t:"Restore;Clean;Build" \
        -m -a x64

# 2. npm install (not 'ci' - upstream lock file is sometimes inconsistent)
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install --no-audit --no-fund

# 3. Vite build of frontend + license bundle
RUN npm run prod-linux

# 4. Bundle .NET 9 runtime tarball into build/Electron/dotnet-runtime/
RUN node ./src-electron/download-dotnet-runtime.js --arch=x64

# 5. Patch package.json version
RUN node ./src-electron/patch-package-version.js

# 6. Pack as unpacked dir (--linux dir bypasses AppImage/FUSE)
RUN ./node_modules/.bin/electron-builder --linux dir --x64 --publish never

# 7. Patch node-api-dotnet DLL paths
RUN node ./src-electron/patch-node-api-dotnet.js --arch=x64

# 8. Move final tree to stable path for stage 2
RUN test -d build/linux-unpacked || (echo "FATAL: build/linux-unpacked missing"; ls -la build/; exit 1) \
    && mv build/linux-unpacked /opt/vrcx-extracted

# ---------- Stage 2: Selkies Wayland single-app runtime ----------
FROM ghcr.io/linuxserver/baseimage-selkies:ubuntunoble

ARG VRCX_REF=master
LABEL org.opencontainers.image.title="VRCX" \
      org.opencontainers.image.description="Self-hosted VRCX in browser via Selkies WebRTC (Wayland + Intel QSV/VAAPI zero-copy)" \
      org.opencontainers.image.source="https://github.com/tio-27/vrcx-docker" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VRCX_REF}"

# Image-level defaults following LSIO Electron-app pattern (cf. docker-obsidian).
# These can still be overridden in compose if needed.
ENV TITLE=VRCX \
    NO_GAMEPAD=true \
    NO_DECOR=true \
    PIXELFLUX_WAYLAND=true

# Runtime deps for Electron 38 on Ubuntu Noble:
# - electron-builder's documented base deps, adjusted for Noble's t64
#   package renames (time_t ABI migration).
# - intel-media-va-driver-non-free unlocks H264/HEVC encode entrypoints
#   needed for the QSV/VAAPI zero-copy stream pipeline.
# - vainfo for the verification step in README/MIGRATION docs.
#
# Own multiverse sources file - works regardless of whether the base image
# uses the old /etc/apt/sources.list or deb822 ubuntu.sources layout. apt
# deduplicates entries so this is safe if multiverse is already enabled.
COPY <<EOF /etc/apt/sources.list.d/multiverse.sources
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-backports
Components: multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

RUN apt-get update && apt-get install -y --no-install-recommends \
        intel-media-va-driver-non-free \
        vainfo \
        libgtk-3-0t64 \
        libnotify4 \
        libnss3 \
        libxss1 \
        libxtst6 \
        libatspi2.0-0t64 \
        libuuid1 \
        libsecret-1-0 \
        libasound2t64 \
        libcups2t64 \
        libdrm2 \
        libgbm1 \
        libxcomposite1 \
        libxdamage1 \
        libxrandr2 \
        libxfixes3 \
        libxkbcommon0 \
        libxshmfence1 \
        libnspr4 \
        libdbus-1-3 \
        libexpat1 \
        libpangocairo-1.0-0 \
        libcurl4t64 \
        xdg-utils \
        fonts-liberation \
        fonts-noto-color-emoji \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# Copy VRCX from builder stage
COPY --from=builder /opt/vrcx-extracted /opt/vrcx
RUN chmod +x /opt/vrcx/vrcx

# Single-app launcher.
# /defaults/autostart is mode-agnostic - svc-de copies it to either
# /config/.config/openbox/ (X11 mode) or /config/.config/labwc/ (Wayland mode)
# depending on PIXELFLUX_WAYLAND. Same script works for both.
COPY files/vrcx-launcher.sh /defaults/autostart
RUN chmod +x /defaults/autostart

# Custom init - belt-and-suspenders. Modern baseimage-selkies with
# RESTART_APP=true should handle this itself, but the script is harmless and
# protects against edge cases where the autostart file ends up without
# exec bit after volume init.
COPY root/ /
RUN chmod +x /custom-cont-init.d/10-fix-autostart.sh
