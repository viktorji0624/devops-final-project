#!/bin/bash
cd "$(dirname "$0")/.."

echo "Starting Docker containers..."
echo "Rebuilding and recreating Jenkins to apply Dockerfile updates (including Ansible)..."
docker compose up -d --build --force-recreate jenkins
docker compose up -d

echo "Verifying Ansible inside Jenkins container..."
docker exec jenkins sh -lc 'command -v ansible-playbook >/dev/null && ansible-playbook --version | head -n 1'

VAGRANT_PROVIDER="${1:-virtualbox}"
echo "Starting Vagrant VM with provider: ${VAGRANT_PROVIDER}"
if ! command -v vagrant >/dev/null 2>&1; then
  echo "WARNING: vagrant not found — skipping VM startup."
  echo "  If running inside a devcontainer, start the VM from the host instead:"
  echo "    vagrant up --provider=${VAGRANT_PROVIDER}"
else
  vagrant up --provider="${VAGRANT_PROVIDER}"
fi

echo "Done. All services running."
echo ""
echo "Jenkins:    http://localhost:8080"
echo "SonarQube:  http://localhost:9000"
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000"
echo "Burp noVNC: http://localhost:6080"
echo "Burp Suite: VNC at localhost:5900"
echo "VM SSH:     vagrant ssh"
echo "VM IP:      192.168.56.10"
