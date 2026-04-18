#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VAGRANT_PROVIDER="${1:-virtualbox}"
SONAR_URL="http://localhost:9000"
JENKINS_URL="http://localhost:8080"
SONAR_USER="admin"
SONAR_PASS="admin"

# ── 1. Start SonarQube first (need its token before Jenkins) ──
echo "==> Starting SonarQube..."
docker compose up -d sonarqube

echo "==> Waiting for SonarQube to be ready..."
until curl -sf "${SONAR_URL}/api/system/status" 2>/dev/null | grep -q '"status":"UP"'; do
  printf '.'
  sleep 5
done
echo " SonarQube is UP"

# ── 2. Generate SonarQube token ──
echo "==> Creating SonarQube project and token..."

# Create project (ignore if already exists)
curl -sf -u "${SONAR_USER}:${SONAR_PASS}" -X POST \
  "${SONAR_URL}/api/projects/create" \
  -d "name=spring-petclinic&project=spring-petclinic" >/dev/null 2>&1 || true

# Revoke old token (ignore if not exists)
curl -sf -u "${SONAR_USER}:${SONAR_PASS}" -X POST \
  "${SONAR_URL}/api/user_tokens/revoke" \
  -d "name=jenkins" >/dev/null 2>&1 || true

# Generate new token
SONAR_TOKEN=$(curl -sf -u "${SONAR_USER}:${SONAR_PASS}" -X POST \
  "${SONAR_URL}/api/user_tokens/generate" \
  -d "name=jenkins" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['token'])")

echo "   SonarQube token generated"

# ── 3. Write .env for docker-compose ──
GIT_REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")

cat > .env <<EOF
SONAR_TOKEN=${SONAR_TOKEN}
GIT_REPO_URL=${GIT_REPO_URL}
EOF
echo "   .env written (SONAR_TOKEN, GIT_REPO_URL)"

# ── 4. Start Vagrant VM (before Docker, so .vagrant/ key is ready for mount) ──
echo "==> Starting Vagrant VM with provider: ${VAGRANT_PROVIDER}"
if ! command -v vagrant >/dev/null 2>&1; then
  echo "   WARNING: vagrant not found — skipping VM startup."
  echo "   The Deploy stage will be skipped in Jenkins."
  echo "   To enable deployment, install Vagrant and run: vagrant up --provider=${VAGRANT_PROVIDER}"
else
  vagrant up --provider="${VAGRANT_PROVIDER}"
  VAGRANT_KEY=$(find .vagrant/machines/default -name private_key -print -quit 2>/dev/null)
  if [ -n "$VAGRANT_KEY" ]; then
    echo "   Vagrant SSH key found: ${VAGRANT_KEY}"
  else
    echo "   WARNING: Vagrant VM started but private_key not found."
  fi
fi

# ── 5. Build and start all Docker services ──
echo "==> Building and starting all services..."
docker compose build jenkins
docker compose up -d

echo "==> Verifying Ansible inside Jenkins container..."
docker exec jenkins sh -lc 'command -v ansible-playbook >/dev/null && ansible-playbook --version | head -n 1' || true

# ── 6. Wait for Jenkins and trigger first pipeline ──
echo "==> Waiting for Jenkins to be ready..."
until curl -sf "${JENKINS_URL}/login" >/dev/null 2>&1; do
  printf '.'
  sleep 5
done
echo " Jenkins is UP"

# Wait a bit more for JCasC to finish loading the job
echo "==> Waiting for pipeline job to be created by JCasC..."
for i in $(seq 1 30); do
  if curl -sf -u admin:admin "${JENKINS_URL}/job/petclinic-pipeline/api/json" >/dev/null 2>&1; then
    echo "   petclinic-pipeline job found"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "   WARNING: petclinic-pipeline job not found after 150s, skipping auto-trigger"
    break
  fi
  sleep 5
done

# Trigger first build
if curl -sf -u admin:admin "${JENKINS_URL}/job/petclinic-pipeline/api/json" >/dev/null 2>&1; then
  echo "==> Triggering first pipeline build..."
  curl -sf -u admin:admin -X POST "${JENKINS_URL}/job/petclinic-pipeline/build" || true
  echo "   Build triggered"
fi

# ── Done ──
echo ""
echo "========================================"
echo " All services running"
echo "========================================"
echo ""
echo "Jenkins:    ${JENKINS_URL}        (admin / admin)"
echo "SonarQube:  ${SONAR_URL}        (admin / admin)"
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000  (admin / admin)"
echo "Burp noVNC: http://localhost:6080"
echo "Burp VNC:   localhost:5900"
echo "VM SSH:     vagrant ssh"
echo "VM App:     http://localhost:8082"
echo ""
