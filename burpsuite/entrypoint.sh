#!/bin/bash

# Start virtual framebuffer
Xvfb :99 -screen 0 1280x1024x24 &
export DISPLAY=:99

# Start a lightweight window manager
fluxbox &

# Start VNC server for remote access
x11vnc -display :99 -forever -nopw -rfbport 5900 &

# Launch Burp Suite Community Edition
java -jar /opt/burpsuite.jar
