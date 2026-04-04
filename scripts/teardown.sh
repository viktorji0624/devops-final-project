#!/bin/bash
cd "$(dirname "$0")/.."

echo "Stopping Docker containers..."
docker compose down

echo "Destroying Vagrant VM..."
vagrant destroy -f

echo "Done. All services stopped."
