# syntax=docker/dockerfile:1

# ---------- Stage 1: Build VRCX from source ----------
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder

ARG VRCX_REF=master

ENV USE_SYSTEM_FPM=true \
    APPIMAGE_EXTRACT_AND_RUN=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates \
        libgbm1 libnss3 libasound2 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libdrm2 libxcomposite1 libxdamage1 libxfixes3 \
        libxkbcommon0 libxrandr2 libxshmfence1 libnspr4 libdbus-1-3 \
        libexpat1 libxcb1 libx11-6 libxext6 libxtst6 libxi6 \
        libpangocairo-1.0-0 libgtk-3-0 \
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/vrcx-team/VRCX.git . \
    && git checkout "${VRCX_REF}"

RUN dotnet build 'Dotnet/VRCX-Electron.csproj' \
        -p:Configuration=Release \
        -p:WarningLevel=0 \
        -p:Platform=x64 \
        -p:PlatformTarget=x64 \
        -p:RestorePackagesConfig=true \
        -t:"Restore;Clean;Build" \
        -m -a x64

RUN npm install --arch=x64
RUN npm run prod-linux --arch=x64

RUN node ./src-electron/patch-package-version.js \
    && ./node_modules/.bin/electron-builder --linux dir --x64 --publish never \
    && node ./src-electron/patch-node-api-dotnet.js \
    && (node ./src-electron/rename-builds.js || echo "rename-builds skipped")

RUN UNPACKED=$(find build/ -maxdepth 2 -type d -name "linux-unpacked" | head -n1) \
    && [ -n "$UNPACKED" ] || (echo "linux-unpacked dir not found"; ls -la build/; exit 1) \
    && mv "$UNPACKED" /opt/vrcx-extracted

# ---------- Stage 2: Webtop runtime (Selkies-based, WebRTC) ----------
FROM lscr.io/linuxserver/webtop:ubuntu-xfce

# .NET 9 runtime + Electron deps
# webtop:ubuntu-xfce is based on Ubuntu Noble (24.04)
# .NET 9 on Noble comes from Canonical's backports PPA (Microsoft no longer publishes for 24.04+)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgbm1 libnss3 libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
        libcups2t64 libdrm2 libxcomposite1 libxdamage1 libxfixes3 \
        libxkbcommon0 libxrandr2 libxshmfence1 libnspr4 libdbus-1-3 \
        libexpat1 libxcb1 libx11-6 libxext6 libxtst6 libxi6 \
        libpangocairo-1.0-0 libgtk-3-0t64 libnotify4 libsecret-1-0 \
        ca-certificates software-properties-common procps \
    && add-apt-repository -y ppa:dotnet/backports \
    && apt-get update \
    && apt-get install -y --no-install-recommends dotnet-runtime-9.0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

# Copy VRCX from builder
COPY --from=builder /opt/vrcx-extracted /opt/vrcx
RUN chmod +x /opt/vrcx/vrcx

# Desktop entry for menu/launcher
COPY files/vrcx.desktop /usr/share/applications/vrcx.desktop

# Webtop's /defaults/autostart is a single executable file (not a dir)
# It's run on container start as the main application launcher
COPY files/vrcx-launcher.sh /defaults/autostart
RUN chmod +x /defaults/autostart