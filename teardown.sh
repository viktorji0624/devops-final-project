#!/bin/bash

echo "Stopping Docker containers..."
docker compose down

echo "Destroying Vagrant VM..."
vagrant destroy -f

echo "Done. All services stopped."
