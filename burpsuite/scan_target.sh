#!/bin/bash
set -euo pipefail

TARGET_BASE_URL="${1:-http://host.docker.internal:8082}"
USE_PROXY="${USE_PROXY:-false}"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:8080}"
REPORT_DIR="${REPORT_DIR:-/reports}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-15}"
REQUIRE_BURP_PROCESS="${REQUIRE_BURP_PROCESS:-true}"
REQUIRE_PROXY_SUCCESS="${REQUIRE_PROXY_SUCCESS:-false}"
REPORT_HTML="${REPORT_DIR}/index.html"

mkdir -p "${REPORT_DIR}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

PATHS=(
  "/"
  "/owners"
  "/vets"
  "/actuator/health"
  "/error"
)

SENSITIVE_PATHS=(
  "/actuator"
  "/actuator/env"
  "/actuator/beans"
  "/actuator/mappings"
  "/actuator/configprops"
  "/actuator/threaddump"
  "/actuator/heapdump"
  "/actuator/prometheus"
  "/swagger-ui/index.html"
  "/v3/api-docs"
  "/h2-console"
  "/.env"
  "/.git/config"
)

ENDPOINT_ROWS=""
SENSITIVE_ROWS=""
FINDING_ROWS=""
FINDING_COUNT=0
BURP_ROWS=""
BURP_PROCESS_OK="false"
BURP_PROXY_OK="false"
BURP_VERSION="unknown"
BURP_WELCOME_OK="false"
BURP_CA_CERT_OK="false"
BURP_HTTP_PROXY_OK="false"
BURP_HTTPS_PROXY_OK="false"
BURP_TARGET_PROXY_OK="false"
BURP_LOOPBACK_OK="false"
BURP_CONTAINER_IP_OK="unknown"
BURP_BIND_SCOPE="unknown"
BURP_CONTAINER_IP=""

parse_proxy_host() {
  local proxy="${PROXY_URL#http://}"
  proxy="${proxy#https://}"
  proxy="${proxy%%/*}"
  echo "${proxy%%:*}"
}

parse_proxy_port() {
  local proxy="${PROXY_URL#http://}"
  proxy="${proxy#https://}"
  proxy="${proxy%%/*}"
  if [[ "${proxy}" == *:* ]]; then
    echo "${proxy##*:}"
  else
    echo "80"
  fi
}

get_header_value() {
  local header_file="$1"
  local header_name="$2"

  awk -F': ' -v h="${header_name}" 'tolower($1)==tolower(h){print $2}' "${header_file}" \
    | tail -n 1 \
    | tr -d '\r' || true
}

add_finding() {
  local severity="$1"
  local title="$2"
  local detail="$3"
  FINDING_COUNT=$((FINDING_COUNT + 1))
  FINDING_ROWS+="<tr><td>${FINDING_COUNT}</td><td>${severity}</td><td>${title}</td><td>${detail}</td></tr>"$'\n'
}

append_burp_row() {
  local item="$1"
  local status="$2"
  local detail="$3"
  BURP_ROWS+="<tr><td>${item}</td><td>${status}</td><td>${detail}</td></tr>"$'\n'
}

http_check() {
  local path="$1"
  local url="${TARGET_BASE_URL}${path}"
  local header_file="${TMP_DIR}/headers_$(echo "${path}" | tr '/:' '__').txt"
  local result
  local code
  local ttotal

  if [ "${USE_PROXY}" = "true" ]; then
    result="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -x "${PROXY_URL}" -D "${header_file}" -o /dev/null -w "%{http_code} %{time_total}" "${url}" || true)"
  else
    result="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -D "${header_file}" -o /dev/null -w "%{http_code} %{time_total}" "${url}" || true)"
  fi

  code="$(echo "${result}" | awk '{print $1}')"
  ttotal="$(echo "${result}" | awk '{print $2}')"
  code="${code: -3}"
  if ! echo "${code}" | grep -Eq '^[0-9]{3}$'; then
    code="000"
  fi
  if [ -z "${ttotal}" ]; then
    ttotal="0"
  fi

  ENDPOINT_ROWS+="<tr><td>${path}</td><td>${code}</td><td>${ttotal}</td></tr>"$'\n'

  if [ "${code}" = "000" ]; then
    add_finding "HIGH" "Endpoint unreachable" "${url} could not be reached within ${TIMEOUT_SECONDS}s."
  elif [ "${code}" -ge 500 ] 2>/dev/null; then
    add_finding "MEDIUM" "Server error response" "${url} returned HTTP ${code}."
  elif [ "${code}" -ge 400 ] 2>/dev/null; then
    add_finding "LOW" "Client error response" "${url} returned HTTP ${code}."
  fi
}

check_header() {
  local header_file="$1"
  local header_name="$2"
  local severity="$3"
  local recommendation="$4"
  local value

  value="$(get_header_value "${header_file}" "${header_name}")"
  if [ -z "${value}" ]; then
    add_finding "${severity}" "Missing security header: ${header_name}" "${recommendation}"
  fi
}

check_cookie_flags() {
  local header_file="$1"
  local cookie_lines
  local cookie_count
  local line
  local name

  cookie_lines="$(awk -F': ' 'tolower($1)=="set-cookie"{print $2}' "${header_file}" | tr -d '\r' || true)"
  cookie_count="$(printf "%s\n" "${cookie_lines}" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [ "${cookie_count}" = "0" ]; then
    append_burp_row "Cookie inspection" "INFO" "No Set-Cookie headers were observed on the base URL"
    return
  fi

  while IFS= read -r line; do
    [ -z "${line}" ] && continue
    name="${line%%=*}"
    if ! printf "%s" "${line}" | grep -qi ';[[:space:]]*HttpOnly'; then
      add_finding "MEDIUM" "Cookie missing HttpOnly" "Cookie ${name} is missing the HttpOnly attribute."
    fi
    if ! printf "%s" "${line}" | grep -qi ';[[:space:]]*SameSite='; then
      add_finding "LOW" "Cookie missing SameSite" "Cookie ${name} is missing the SameSite attribute."
    fi
    if echo "${TARGET_BASE_URL}" | grep -q '^https://'; then
      if ! printf "%s" "${line}" | grep -qi ';[[:space:]]*Secure'; then
        add_finding "MEDIUM" "Cookie missing Secure" "Cookie ${name} is missing the Secure attribute on an HTTPS target."
      fi
    fi
  done <<< "${cookie_lines}"

  append_burp_row "Cookie inspection" "OK" "Inspected ${cookie_count} Set-Cookie header(s) on the base URL"
}

check_cors_policy() {
  local header_file="${TMP_DIR}/cors_headers.txt"
  local code
  local acao
  local acac
  local acam

  if [ "${USE_PROXY}" = "true" ]; then
    code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -x "${PROXY_URL}" -H 'Origin: https://evil.example' -D "${header_file}" -o /dev/null -w "%{http_code}" "${TARGET_BASE_URL}/" || true)"
  else
    code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -H 'Origin: https://evil.example' -D "${header_file}" -o /dev/null -w "%{http_code}" "${TARGET_BASE_URL}/" || true)"
  fi

  code="${code: -3}"
  acao="$(get_header_value "${header_file}" "Access-Control-Allow-Origin")"
  acac="$(get_header_value "${header_file}" "Access-Control-Allow-Credentials")"
  acam="$(get_header_value "${header_file}" "Access-Control-Allow-Methods")"

  if [ -z "${acao}" ]; then
    append_burp_row "CORS policy" "INFO" "No Access-Control-Allow-Origin header was returned for a cross-origin probe"
    return
  fi

  append_burp_row "CORS policy" "OK" "Cross-origin probe returned HTTP ${code} with ACAO=${acao}"

  if [ "${acao}" = "*" ]; then
    add_finding "MEDIUM" "Permissive CORS policy" "Access-Control-Allow-Origin is '*' on the base URL."
  elif [ "${acao}" = "https://evil.example" ]; then
    add_finding "HIGH" "Reflected CORS origin" "The application reflected the supplied Origin header in Access-Control-Allow-Origin."
  fi

  if [ "${acac}" = "true" ] && { [ "${acao}" = "*" ] || [ "${acao}" = "https://evil.example" ]; }; then
    add_finding "HIGH" "Credentialed CORS exposure" "Cross-origin credentials are allowed with a permissive or reflected origin."
  fi

  if printf "%s" "${acam}" | grep -Eiq '(^|[ ,])(PUT|DELETE|PATCH)([ ,]|$)'; then
    add_finding "LOW" "Cross-origin unsafe methods advertised" "Access-Control-Allow-Methods advertises state-changing methods: ${acam}"
  fi
}

check_http_methods() {
  local header_file="${TMP_DIR}/options_headers.txt"
  local code
  local allow
  local trace_code

  if [ "${USE_PROXY}" = "true" ]; then
    code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -x "${PROXY_URL}" -X OPTIONS -D "${header_file}" -o /dev/null -w "%{http_code}" "${TARGET_BASE_URL}/" || true)"
    trace_code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -x "${PROXY_URL}" -X TRACE -o /dev/null -w "%{http_code}" "${TARGET_BASE_URL}/" || true)"
  else
    code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -X OPTIONS -D "${header_file}" -o /dev/null -w "%{http_code}" "${TARGET_BASE_URL}/" || true)"
    trace_code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -X TRACE -o /dev/null -w "%{http_code}" "${TARGET_BASE_URL}/" || true)"
  fi

  code="${code: -3}"
  trace_code="${trace_code: -3}"
  allow="$(get_header_value "${header_file}" "Allow")"

  if [ -n "${allow}" ]; then
    append_burp_row "Allowed methods" "OK" "OPTIONS probe returned HTTP ${code} with Allow=${allow}"
    if printf "%s" "${allow}" | grep -Eiq '(^|[ ,])(PUT|DELETE|PATCH)([ ,]|$)'; then
      add_finding "LOW" "Potentially dangerous HTTP methods exposed" "Allow header includes state-changing methods: ${allow}"
    fi
  else
    append_burp_row "Allowed methods" "INFO" "OPTIONS probe returned HTTP ${code} without an Allow header"
  fi

  if [ "${trace_code}" != "405" ] && [ "${trace_code}" != "501" ] && [ "${trace_code}" != "000" ]; then
    add_finding "MEDIUM" "TRACE method appears enabled" "TRACE request to the base URL returned HTTP ${trace_code}."
  fi
}

probe_sensitive_path() {
  local path="$1"
  local severity="$2"
  local title="$3"
  local url="${TARGET_BASE_URL}${path}"
  local code

  if [ "${USE_PROXY}" = "true" ]; then
    code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -x "${PROXY_URL}" -o /dev/null -w "%{http_code}" "${url}" || true)"
  else
    code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -o /dev/null -w "%{http_code}" "${url}" || true)"
  fi

  code="${code: -3}"
  if ! echo "${code}" | grep -Eq '^[0-9]{3}$'; then
    code="000"
  fi

  SENSITIVE_ROWS+="<tr><td>${path}</td><td>${code}</td><td>${title}</td></tr>"$'\n'

  case "${code}" in
    200|201|202|204)
      add_finding "${severity}" "${title}" "${url} is directly accessible and returned HTTP ${code}."
      ;;
    401|403)
      ;;
  esac
}

check_sensitive_endpoints() {
  probe_sensitive_path "/actuator" "LOW" "Actuator root exposed"
  probe_sensitive_path "/actuator/env" "HIGH" "Spring environment endpoint exposed"
  probe_sensitive_path "/actuator/beans" "MEDIUM" "Spring beans endpoint exposed"
  probe_sensitive_path "/actuator/mappings" "MEDIUM" "Spring mappings endpoint exposed"
  probe_sensitive_path "/actuator/configprops" "MEDIUM" "Spring configprops endpoint exposed"
  probe_sensitive_path "/actuator/threaddump" "HIGH" "Thread dump endpoint exposed"
  probe_sensitive_path "/actuator/heapdump" "HIGH" "Heap dump endpoint exposed"
  probe_sensitive_path "/actuator/prometheus" "LOW" "Prometheus metrics endpoint exposed"
  probe_sensitive_path "/swagger-ui/index.html" "LOW" "Swagger UI exposed"
  probe_sensitive_path "/v3/api-docs" "LOW" "OpenAPI schema exposed"
  probe_sensitive_path "/h2-console" "MEDIUM" "H2 console exposed"
  probe_sensitive_path "/.env" "HIGH" "dotenv file exposed"
  probe_sensitive_path "/.git/config" "HIGH" "Git metadata exposed"
}

check_burp_version() {
  local version_output

  version_output="$(java -jar /opt/burpsuite.jar --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
  if [ -n "${version_output}" ]; then
    BURP_VERSION="${version_output}"
    append_burp_row "Burp version" "OK" "${BURP_VERSION}"
  else
    append_burp_row "Burp version" "WARN" "Unable to read Burp version from the installed jar"
  fi
}

check_burp_process() {
  if ps -ef | grep -E 'java .*burpsuite\.jar' | grep -v grep >/dev/null 2>&1; then
    BURP_PROCESS_OK="true"
    append_burp_row "Burp process" "OK" "java -jar /opt/burpsuite.jar detected"
  else
    BURP_PROCESS_OK="false"
    append_burp_row "Burp process" "FAILED" "Burp process not detected"
    add_finding "HIGH" "Burp runtime missing" "Burp process (burpsuite.jar) was not found in container process list."
  fi
}

check_direct_burp_endpoint() {
  local proxy_host="$1"
  local proxy_port="$2"
  local direct_url="http://${proxy_host}:${proxy_port}/"
  local cert_url="http://${proxy_host}:${proxy_port}/cert"
  local body_file="${TMP_DIR}/burp_welcome.html"
  local cert_file="${TMP_DIR}/burp_cert.der"
  local code
  local cert_size

  code="$(curl -sS --max-time "${TIMEOUT_SECONDS}" -o "${body_file}" -w "%{http_code}" "${direct_url}" || true)"
  code="${code: -3}"
  if grep -q "Burp Suite Community Edition" "${body_file}" 2>/dev/null; then
    BURP_WELCOME_OK="true"
    append_burp_row "Burp welcome page" "OK" "Direct GET ${direct_url} returned Burp's built-in page (HTTP ${code})"
  else
    append_burp_row "Burp welcome page" "WARN" "Direct GET ${direct_url} did not return Burp's built-in page"
  fi

  code="$(curl -sS --max-time "${TIMEOUT_SECONDS}" -o "${cert_file}" -w "%{http_code}" "${cert_url}" || true)"
  code="${code: -3}"
  cert_size="$(wc -c < "${cert_file}" 2>/dev/null || echo 0)"
  if [ "${code}" = "200" ] && [ "${cert_size}" -gt 0 ]; then
    BURP_CA_CERT_OK="true"
    append_burp_row "Burp CA certificate" "OK" "GET ${cert_url} returned ${cert_size} bytes"
  else
    append_burp_row "Burp CA certificate" "WARN" "GET ${cert_url} did not return a certificate payload"
  fi
}

check_proxy_forward() {
  local url="$1"
  local label="$2"
  local status_var="$3"
  local code

  code="$(curl -sS -k --max-time "${TIMEOUT_SECONDS}" -x "${PROXY_URL}" -o /dev/null -w "%{http_code}" "${url}" || true)"
  code="${code: -3}"
  if echo "${code}" | grep -Eq '^[0-9]{3}$' && [ "${code}" != "000" ]; then
    printf -v "${status_var}" '%s' "true"
    append_burp_row "${label}" "OK" "Proxy forwarded ${url} (HTTP ${code})"
  else
    printf -v "${status_var}" '%s' "false"
    append_burp_row "${label}" "WARN" "Proxy listener is reachable, but forwarding ${url} did not complete"
  fi
}

check_burp_proxy() {
  local proxy_host
  local proxy_port
  local container_ip

  proxy_host="$(parse_proxy_host)"
  proxy_port="$(parse_proxy_port)"
  container_ip="$(hostname -i 2>/dev/null | awk '{print $1}' || true)"
  BURP_CONTAINER_IP="${container_ip}"

  if timeout "${TIMEOUT_SECONDS}" bash -c "exec 3<>/dev/tcp/${proxy_host}/${proxy_port}" >/dev/null 2>&1; then
    BURP_PROXY_OK="true"
    BURP_LOOPBACK_OK="true"
    append_burp_row "Burp proxy listener" "OK" "TCP listener is accepting connections on ${proxy_host}:${proxy_port}"
  else
    BURP_PROXY_OK="false"
    BURP_LOOPBACK_OK="false"
    append_burp_row "Burp proxy listener" "FAILED" "TCP listener is not accepting connections on ${proxy_host}:${proxy_port}"
    add_finding "HIGH" "Burp proxy unavailable" "Cannot connect to proxy listener ${proxy_host}:${proxy_port}."
    return
  fi

  check_direct_burp_endpoint "${proxy_host}" "${proxy_port}"

  if [ -n "${container_ip}" ] && [ "${container_ip}" != "${proxy_host}" ]; then
    if timeout "${TIMEOUT_SECONDS}" bash -c "exec 3<>/dev/tcp/${container_ip}/${proxy_port}" >/dev/null 2>&1; then
      BURP_CONTAINER_IP_OK="true"
      BURP_BIND_SCOPE="all-interfaces"
      append_burp_row "Burp container-network listener" "OK" "TCP listener is reachable on ${container_ip}:${proxy_port}"
    else
      BURP_CONTAINER_IP_OK="false"
      BURP_BIND_SCOPE="loopback-only"
      append_burp_row "Burp container-network listener" "WARN" "TCP listener is not reachable on ${container_ip}:${proxy_port}; Burp appears loopback-only"
    fi
  else
    append_burp_row "Burp container-network listener" "WARN" "Container IP could not be determined"
  fi

  check_proxy_forward "http://example.com/" "Burp proxy forward (HTTP)" BURP_HTTP_PROXY_OK
  check_proxy_forward "https://example.com/" "Burp proxy forward (HTTPS)" BURP_HTTPS_PROXY_OK
  check_proxy_forward "${TARGET_BASE_URL}/" "Burp proxy forward (target)" BURP_TARGET_PROXY_OK
}

echo "[INFO] Target base URL: ${TARGET_BASE_URL}"
echo "[INFO] USE_PROXY=${USE_PROXY}"
if [ "${USE_PROXY}" = "true" ]; then
  echo "[INFO] PROXY_URL=${PROXY_URL}"
fi
echo "[INFO] REQUIRE_BURP_PROCESS=${REQUIRE_BURP_PROCESS}"
echo "[INFO] REQUIRE_PROXY_SUCCESS=${REQUIRE_PROXY_SUCCESS}"
echo "[INFO] Sending requests from burpsuite container..."

check_burp_version
check_burp_process
check_burp_proxy

if [ "${REQUIRE_BURP_PROCESS}" = "true" ] && [ "${BURP_PROCESS_OK}" != "true" ]; then
  echo "[ERROR] Burp process check failed and REQUIRE_BURP_PROCESS=true"
fi

if [ "${USE_PROXY}" = "true" ] && [ "${REQUIRE_PROXY_SUCCESS}" = "true" ] && [ "${BURP_PROXY_OK}" != "true" ]; then
  echo "[ERROR] Burp proxy check failed and REQUIRE_PROXY_SUCCESS=true"
fi

for path in "${PATHS[@]}"; do
  http_check "${path}"
done

ROOT_HEADER_FILE="${TMP_DIR}/headers__.txt"

check_header "${ROOT_HEADER_FILE}" "X-Content-Type-Options" "MEDIUM" "Set X-Content-Type-Options: nosniff"
check_header "${ROOT_HEADER_FILE}" "X-Frame-Options" "MEDIUM" "Set X-Frame-Options: DENY or SAMEORIGIN"
check_header "${ROOT_HEADER_FILE}" "Content-Security-Policy" "HIGH" "Define a strict Content-Security-Policy"
check_header "${ROOT_HEADER_FILE}" "Referrer-Policy" "LOW" "Set Referrer-Policy to limit leaked referrer data"
check_header "${ROOT_HEADER_FILE}" "Permissions-Policy" "LOW" "Set Permissions-Policy to disable unused browser features"
check_header "${ROOT_HEADER_FILE}" "Cross-Origin-Opener-Policy" "LOW" "Set Cross-Origin-Opener-Policy to reduce cross-window attack surface"
check_header "${ROOT_HEADER_FILE}" "Cross-Origin-Resource-Policy" "LOW" "Set Cross-Origin-Resource-Policy for sensitive resources"

SERVER_HEADER="$(get_header_value "${ROOT_HEADER_FILE}" "Server")"
if [ -n "${SERVER_HEADER}" ]; then
  add_finding "LOW" "Server header exposed" "Server header value detected: ${SERVER_HEADER}"
fi

X_POWERED_BY="$(get_header_value "${ROOT_HEADER_FILE}" "X-Powered-By")"
if [ -n "${X_POWERED_BY}" ]; then
  add_finding "LOW" "X-Powered-By header exposed" "X-Powered-By header value detected: ${X_POWERED_BY}"
fi

if echo "${TARGET_BASE_URL}" | grep -q '^http://'; then
  add_finding "MEDIUM" "Plain HTTP target" "Target uses HTTP. Prefer HTTPS in production and CI security tests."
else
  check_header "${ROOT_HEADER_FILE}" "Strict-Transport-Security" "MEDIUM" "Set Strict-Transport-Security for HTTPS deployments"
fi

check_cookie_flags "${ROOT_HEADER_FILE}"
check_cors_policy
check_http_methods
check_sensitive_endpoints

if [ "${FINDING_COUNT}" -eq 0 ]; then
  FINDING_ROWS="<tr><td colspan=\"4\">No findings in baseline checks.</td></tr>"
fi

cat > "${REPORT_HTML}" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Baseline Security Scan Report</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 24px; color: #1f2937; }
    h1, h2 { margin-bottom: 8px; }
    .meta { margin-bottom: 16px; color: #374151; }
    table { border-collapse: collapse; width: 100%; margin: 12px 0 24px; }
    th, td { border: 1px solid #d1d5db; padding: 8px; text-align: left; vertical-align: top; }
    th { background: #f3f4f6; }
    .note { background: #eef6ff; border: 1px solid #93c5fd; padding: 10px; margin-top: 16px; }
  </style>
</head>
<body>
  <h1>Baseline Security Scan Report</h1>
  <div class="meta">
    <div><strong>Target:</strong> ${TARGET_BASE_URL}</div>
    <div><strong>Scan Time:</strong> $(date)</div>
    <div><strong>Mode:</strong> $( [ "${USE_PROXY}" = "true" ] && echo "Proxy via ${PROXY_URL}" || echo "Direct" )</div>
    <div><strong>Total Findings:</strong> ${FINDING_COUNT}</div>
  </div>

  <h2>Endpoint Reachability</h2>
  <table>
    <thead>
      <tr><th>Path</th><th>HTTP Status</th><th>Response Time (s)</th></tr>
    </thead>
    <tbody>
      ${ENDPOINT_ROWS}
    </tbody>
  </table>

  <h2>Burp Capability Evidence</h2>
  <table>
    <thead>
      <tr><th>Check</th><th>Status</th><th>Detail</th></tr>
    </thead>
    <tbody>
      ${BURP_ROWS}
    </tbody>
  </table>

  <h2>Sensitive Endpoint Probes</h2>
  <table>
    <thead>
      <tr><th>Path</th><th>HTTP Status</th><th>Purpose</th></tr>
    </thead>
    <tbody>
      ${SENSITIVE_ROWS}
    </tbody>
  </table>

  <h2>Execution Summary</h2>
  <table>
    <thead>
      <tr><th>Key</th><th>Value</th></tr>
    </thead>
    <tbody>
      <tr><td>burp_version</td><td>${BURP_VERSION}</td></tr>
      <tr><td>burp_process_ok</td><td>${BURP_PROCESS_OK}</td></tr>
      <tr><td>burp_proxy_ok</td><td>${BURP_PROXY_OK}</td></tr>
      <tr><td>burp_loopback_ok</td><td>${BURP_LOOPBACK_OK}</td></tr>
      <tr><td>burp_welcome_ok</td><td>${BURP_WELCOME_OK}</td></tr>
      <tr><td>burp_ca_cert_ok</td><td>${BURP_CA_CERT_OK}</td></tr>
      <tr><td>burp_http_proxy_ok</td><td>${BURP_HTTP_PROXY_OK}</td></tr>
      <tr><td>burp_https_proxy_ok</td><td>${BURP_HTTPS_PROXY_OK}</td></tr>
      <tr><td>burp_target_proxy_ok</td><td>${BURP_TARGET_PROXY_OK}</td></tr>
      <tr><td>burp_bind_scope</td><td>${BURP_BIND_SCOPE}</td></tr>
      <tr><td>burp_container_ip</td><td>${BURP_CONTAINER_IP}</td></tr>
      <tr><td>burp_container_ip_ok</td><td>${BURP_CONTAINER_IP_OK}</td></tr>
      <tr><td>require_burp_process</td><td>${REQUIRE_BURP_PROCESS}</td></tr>
      <tr><td>require_proxy_success</td><td>${REQUIRE_PROXY_SUCCESS}</td></tr>
    </tbody>
  </table>

  <h2>Baseline Findings</h2>
  <table>
    <thead>
      <tr><th>#</th><th>Severity</th><th>Finding</th><th>Detail</th></tr>
    </thead>
    <tbody>
      ${FINDING_ROWS}
    </tbody>
  </table>

  <div class="note">
    This is a baseline scripted check report (connectivity, passive security checks, sensitive endpoint probes, and Burp capability evidence), not a full DAST vulnerability audit.
    For full DAST with automated vulnerability HTML reports, use Burp Suite Professional or OWASP ZAP in CI.
  </div>
</body>
</html>
EOF

echo "[INFO] HTML report: ${REPORT_HTML}"

if [ "${REQUIRE_BURP_PROCESS}" = "true" ] && [ "${BURP_PROCESS_OK}" != "true" ]; then
  exit 2
fi

if [ "${USE_PROXY}" = "true" ] && [ "${REQUIRE_PROXY_SUCCESS}" = "true" ] && [ "${BURP_PROXY_OK}" != "true" ]; then
  exit 3
fi

echo "[DONE] Target hit flow finished."
