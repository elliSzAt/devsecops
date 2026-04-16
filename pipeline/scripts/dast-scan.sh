#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  DAST: OWASP ZAP Scan"
echo "============================================"

REPORT_DIR="${REPORT_DIR:-./reports}"
TARGET_URL="${APP_URL:-http://localhost:3000}"
CONTAINER_NAME="devsecops-app"
ZAP_RULES_FILE="${ZAP_RULES_FILE:-}"
SCAN_EXIT=0
APP_NETWORK=""

mkdir -p "$REPORT_DIR"

if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
  APP_NETWORK=$(docker inspect "${CONTAINER_NAME}" --format='{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || echo "")
  APP_IP=$(docker inspect "${CONTAINER_NAME}" --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
  if [ -n "$APP_IP" ]; then
    TARGET_URL="http://${APP_IP}:3000"
    echo "[ZAP] Resolved container IP: ${APP_IP}"
  fi
fi

echo "[ZAP] Target: ${TARGET_URL}"
echo "[ZAP] Starting OWASP ZAP baseline scan..."

ZAP_DOCKER_ARGS=(
  --rm
  -v "$(pwd)/${REPORT_DIR}:/zap/wrk:rw"
)

if [ -n "$APP_NETWORK" ]; then
  ZAP_DOCKER_ARGS+=(--network "${APP_NETWORK}")
fi

docker run "${ZAP_DOCKER_ARGS[@]}" \
  zaproxy/zap-stable:2.16.0 \
  zap-baseline.py \
  -t "${TARGET_URL}" \
  -J dast-report.json \
  -r dast-report.html \
  -l WARN \
  -I \
  || SCAN_EXIT=$?

if [ ! -f "${REPORT_DIR}/dast-report.json" ]; then
  echo "[ZAP] ERROR: No DAST report generated!"
  exit 1
fi

ALERT_SUMMARY=$(python3 << PYEOF
import json

with open("${REPORT_DIR}/dast-report.json") as f:
    data = json.load(f)

high = med = low = info = 0
for site in data.get("site", []):
    for alert in site.get("alerts", []):
        risk = alert.get("riskdesc", "").split(" ")[0].lower()
        if risk == "high": high += 1
        elif risk == "medium": med += 1
        elif risk == "low": low += 1
        elif risk == "informational": info += 1

print(f"{high} {med} {low} {info}")
PYEOF
)

HIGH=$(echo "$ALERT_SUMMARY" | awk '{print $1}')
MEDIUM=$(echo "$ALERT_SUMMARY" | awk '{print $2}')
LOW=$(echo "$ALERT_SUMMARY" | awk '{print $3}')
INFO=$(echo "$ALERT_SUMMARY" | awk '{print $4}')

echo ""
echo "[ZAP] ======= DAST SCAN SUMMARY ======="
echo "[ZAP] Target:        ${TARGET_URL}"
echo "[ZAP] High Risk:     ${HIGH}"
echo "[ZAP] Medium Risk:   ${MEDIUM}"
echo "[ZAP] Low Risk:      ${LOW}"
echo "[ZAP] Informational: ${INFO}"
echo "[ZAP] Report JSON:   ${REPORT_DIR}/dast-report.json"
echo "[ZAP] Report HTML:   ${REPORT_DIR}/dast-report.html"
echo "[ZAP] ======================================"

if [ "$HIGH" -gt 0 ]; then
  echo ""
  echo "[ZAP] PIPELINE BLOCKED: ${HIGH} High-risk vulnerabilities found!"
  echo "[ZAP] Triggering ROLLBACK."
  exit 1
fi

echo "[ZAP] DAST scan passed - no High-risk vulnerabilities."
