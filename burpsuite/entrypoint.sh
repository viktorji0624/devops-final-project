#!/bin/bash
set -euo pipefail

rm -f /tmp/.X99-lock
rm -f /tmp/.X11-unix/X99

Xvfb :99 -screen 0 1280x1024x24 &
export DISPLAY=:99

for _ in {1..20}; do
  if [ -S /tmp/.X11-unix/X99 ]; then
    break
  fi
  sleep 0.5
done

fluxbox >/tmp/fluxbox.log 2>&1 &
x11vnc -display :99 -forever -nopw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
/usr/share/novnc/utils/novnc_proxy --listen 6080 --vnc localhost:5900 >/tmp/novnc.log 2>&1 &

echo "[entrypoint] Starting Burp with container-local user state"
exec java -jar /opt/burpsuite.jar --use-defaults
