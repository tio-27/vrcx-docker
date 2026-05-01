# syntax=docker/dockerfile:1.7

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

# Build order per official VRCX wiki: dotnet first, then npm
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

# electron-builder --dir: produces unpacked tree (no AppImage, no FUSE issue)
# Replicates npm run build-electron + postbuild-electron sequence
RUN node ./src-electron/patch-package-version.js \
    && ./node_modules/.bin/electron-builder --linux dir --x64 --publish never \
    && node ./src-electron/patch-node-api-dotnet.js \
    && (node ./src-electron/rename-builds.js || echo "rename-builds skipped (no AppImage to rename)")

# Locate unpacked output
RUN UNPACKED=$(find build/ -maxdepth 2 -type d -name "linux-unpacked" | head -n1) \
    && [ -n "$UNPACKED" ] || (echo "linux-unpacked dir not found"; ls -la build/; exit 1) \
    && mv "$UNPACKED" /opt/vrcx-extracted \
    && ls -la /opt/vrcx-extracted

# ---------- Stage 2: Kasm runtime ----------
FROM kasmweb/core-ubuntu-jammy:1.18.0

USER root

ENV HOME=/home/kasm-default-profile \
    STARTUPDIR=/dockerstartup \
    INST_SCRIPTS=/dockerstartup/install \
    DEBIAN_FRONTEND=noninteractive

WORKDIR $HOME

######### Customize Container Here ###########

# Runtime deps for Electron + .NET 9
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgbm1 libnss3 libasound2 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libdrm2 libxcomposite1 libxdamage1 libxfixes3 \
        libxkbcommon0 libxrandr2 libxshmfence1 libnspr4 libdbus-1-3 \
        libexpat1 libxcb1 libx11-6 libxext6 libxtst6 libxi6 \
        libpangocairo-1.0-0 libgtk-3-0 libnotify4 libsecret-1-0 \
        tzdata wget ca-certificates procps \
    && wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/ms.deb \
    && dpkg -i /tmp/ms.deb && rm /tmp/ms.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends dotnet-runtime-9.0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

# Copy unpacked VRCX from builder stage
COPY --from=builder /opt/vrcx-extracted /opt/vrcx
RUN chmod +x /opt/vrcx/vrcx

# Desktop entry, autostart script, KasmVNC user config
COPY files/vrcx.desktop /usr/share/applications/vrcx.desktop
COPY files/custom_startup.sh $STARTUPDIR/custom_startup.sh
COPY files/kasmvnc.yaml $HOME/.vnc/kasmvnc.yaml

RUN mkdir -p $HOME/Desktop \
    && cp /usr/share/applications/vrcx.desktop $HOME/Desktop/vrcx.desktop \
    && chmod +x $HOME/Desktop/vrcx.desktop \
    && chmod +x $STARTUPDIR/custom_startup.sh \
    && chmod 644 $HOME/.vnc/kasmvnc.yaml \
    && chown 1000:1000 $HOME/Desktop/vrcx.desktop $STARTUPDIR/custom_startup.sh $HOME/.vnc/kasmvnc.yaml

# Persistent VRCX config directory
RUN mkdir -p $HOME/.config/VRCX \
    && chown -R 1000:1000 $HOME/.config

######### End Customizations ###########

RUN chown 1000:0 $HOME \
    && $STARTUPDIR/set_user_permission.sh $HOME

ENV HOME=/home/kasm-user
WORKDIR $HOME
RUN mkdir -p $HOME && chown -R 1000:0 $HOME

USER 1000