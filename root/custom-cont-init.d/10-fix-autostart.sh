#!/usr/bin/with-contenv bash
# Force-sync /defaults/autostart to user config with exec bit on every boot.
# Selkies' init-config copies but loses exec permission, so we fix it here.

mkdir -p /config/.config/openbox
cp -f /defaults/autostart /config/.config/openbox/autostart
chmod +x /config/.config/openbox/autostart
chown abc:abc /config/.config/openbox/autostart
