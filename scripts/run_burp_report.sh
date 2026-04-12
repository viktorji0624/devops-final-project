#!/bin/bash
set -euo pipefail

TARGET_URL="${1:-http://host.docker.internal:8082}"
REPORT_DIR="${REPORT_DIR:-reports/burp}"

mkdir -p "${REPORT_DIR}"
find "${REPORT_DIR}" -mindepth 1 -maxdepth 1 ! -name 'index.html' -delete
rm -f "${REPORT_DIR}/index.html"

for _ in $(seq 1 30); do
  if docker exec burpsuite bash -lc 'exec 3<>/dev/tcp/127.0.0.1/8080' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec \
  -e USE_PROXY=true \
  -e PROXY_URL=http://127.0.0.1:8080 \
  -e REPORT_DIR=/reports \
  -e REQUIRE_BURP_PROCESS=true \
  -e REQUIRE_PROXY_SUCCESS=true \
  burpsuite \
  /scan_target.sh "${TARGET_URL}"

echo "[DONE] Burp report ready at ${REPORT_DIR}/index.html"
