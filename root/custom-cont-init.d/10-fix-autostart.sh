#!/usr/bin/with-contenv bash
# Defensive copy of /defaults/autostart with exec bit to both possible
# compositor config dirs. Modern baseimage-selkies with RESTART_APP=true
# manages this itself, but keeping it as belt-and-suspenders protects
# against edge cases where /config volume init drops the exec bit.

for sub in openbox labwc; do
    mkdir -p "/config/.config/${sub}"
    cp -f /defaults/autostart "/config/.config/${sub}/autostart"
    chmod +x "/config/.config/${sub}/autostart"
    chown abc:abc "/config/.config/${sub}/autostart"
done
