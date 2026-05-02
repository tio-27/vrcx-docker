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
# Falls back to full clone if --depth 1 --branch fails (rare with old refs)
RUN git clone --depth 1 --branch "${VRCX_REF}" https://github.com/vrcx-team/VRCX.git . \
    || (git clone https://github.com/vrcx-team/VRCX.git . && git checkout "${VRCX_REF}")

# 1. Build .NET 9 Electron-side assembly (VRCX-Electron.csproj)
#    BuildKit cache mount speeds up incremental builds dramatically
RUN --mount=type=cache,target=/root/.nuget/packages,sharing=locked \
    dotnet build 'Dotnet/VRCX-Electron.csproj' \
        -p:Configuration=Release \
        -p:WarningLevel=0 \
        -p:Platform=x64 \
        -p:PlatformTarget=x64 \
        -p:RestorePackagesConfig=true \
        -t:"Restore;Clean;Build" \
        -m -a x64

# 2. npm install
#    Note: We use 'install' instead of 'ci' because VRCX upstream's package-lock.json
#    is sometimes out of sync with package.json (e.g. missing transitive deps).
#    'ci' fails strict, 'install' resolves on the fly.
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install --no-audit --no-fund

# 3. Vite build of frontend + license bundle (npm run prod-linux includes both)
RUN npm run prod-linux

# 4. Download bundled .NET 9 runtime tarball into build/Electron/dotnet-runtime/
#    REQUIRED step - VRCX's main.js prefers this bundled runtime at startup
RUN node ./src-electron/download-dotnet-runtime.js --arch=x64

# 5. Patch package.json version (must run before electron-builder)
RUN node ./src-electron/patch-package-version.js

# 6. Pack as unpacked dir - --linux dir overrides AppImage default from package.json
#    This bypasses FUSE which is unavailable in Docker build context
RUN ./node_modules/.bin/electron-builder --linux dir --x64 --publish never

# 7. Post-build: patch node-api-dotnet DLL paths
RUN node ./src-electron/patch-node-api-dotnet.js --arch=x64

# 8. Move final tree to a stable path for stage 2
#    package.json sets directories.output=build, so unpacked = build/linux-unpacked
RUN test -d build/linux-unpacked || (echo "FATAL: build/linux-unpacked missing"; ls -la build/; exit 1) \
    && mv build/linux-unpacked /opt/vrcx-extracted

# ---------- Stage 2: Selkies single-app runtime ----------
FROM ghcr.io/linuxserver/baseimage-selkies:ubuntunoble

ARG VRCX_REF=master
LABEL org.opencontainers.image.title="VRCX" \
      org.opencontainers.image.description="Self-hosted VRCX in browser via Selkies WebRTC" \
      org.opencontainers.image.source="https://github.com/tio-27/vrcx-docker" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VRCX_REF}"

# Electron runtime libs + .NET 9 fallback runtime
# Note: VRCX bundles its own .NET 9 in app.asar.unpacked, but installing the
# system runtime as fallback is harmless and helps if the bundled copy ever fails to load.
# Microsoft no longer publishes .NET for Ubuntu Noble (24.04+) - only Canonical's PPA does.
# We add the PPA manually (without add-apt-repository) to avoid launchpad.net API timeouts.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgbm1 libnss3 libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
        libcups2t64 libdrm2 libxcomposite1 libxdamage1 libxfixes3 \
        libxkbcommon0 libxrandr2 libxshmfence1 libnspr4 libdbus-1-3 \
        libexpat1 libxcb1 libx11-6 libxext6 libxtst6 libxi6 \
        libpangocairo-1.0-0 libgtk-3-0t64 libnotify4 libsecret-1-0 \
        ca-certificates gnupg curl \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF" \
        | gpg --dearmor -o /etc/apt/keyrings/dotnet-backports.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/dotnet-backports.gpg] https://ppa.launchpadcontent.net/dotnet/backports/ubuntu noble main" \
        > /etc/apt/sources.list.d/dotnet-backports.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends dotnet-runtime-9.0 \
    && apt-get purge -y gnupg curl \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# Copy VRCX from builder stage
COPY --from=builder /opt/vrcx-extracted /opt/vrcx
RUN chmod +x /opt/vrcx/vrcx

# Single-app launcher - Openbox calls this after init in the user X session
COPY files/vrcx-launcher.sh /defaults/autostart
RUN chmod +x /defaults/autostart