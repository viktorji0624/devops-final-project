#!/bin/bash
cd "$(dirname "$0")/.."

echo "Starting Docker containers..."
docker compose up -d

echo "Starting Vagrant VM..."
vagrant up --provider=${1:-vmware_desktop}

echo "Done. All services running."
echo ""
echo "Jenkins:    http://localhost:8080"
echo "SonarQube:  http://localhost:9000"
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000"
echo "Burp Suite: VNC at localhost:5900"
echo "VM SSH:     vagrant ssh"
echo "VM IP:      192.168.56.10"
