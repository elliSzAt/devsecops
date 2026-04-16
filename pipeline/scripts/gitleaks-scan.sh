#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  SAST: Gitleaks - Secret Scanning"
echo "============================================"

REPORT_DIR="${REPORT_DIR:-./reports}"
WORKSPACE="${GITHUB_WORKSPACE:-.}"
SCAN_EXIT=0

mkdir -p "$REPORT_DIR"

run_with_docker() {
  echo "[Gitleaks] Running via Docker..."
  docker run --rm \
    -v "${WORKSPACE}:/src" \
    zricethezav/gitleaks:latest \
    detect \
    --source="/src" \
    --report-format=json \
    --report-path="/src/${REPORT_DIR}/gitleaks-report.json" \
    --exit-code=1 \
    || SCAN_EXIT=$?
}

run_native() {
  echo "[Gitleaks] Running native binary..."
  gitleaks detect \
    --source="${WORKSPACE}" \
    --report-format=json \
    --report-path="${REPORT_DIR}/gitleaks-report.json" \
    --exit-code=1 \
    || SCAN_EXIT=$?
}

if command -v gitleaks &>/dev/null; then
  run_native
elif command -v docker &>/dev/null; then
  run_with_docker
else
  echo "[Gitleaks] ERROR: Neither gitleaks nor docker found!"
  exit 1
fi

if [ ! -f "${REPORT_DIR}/gitleaks-report.json" ]; then
  echo "[]" > "${REPORT_DIR}/gitleaks-report.json"
fi

LEAK_COUNT=$(python3 -c "
import json
with open('${REPORT_DIR}/gitleaks-report.json') as f:
    data = json.load(f)
    print(len(data) if isinstance(data, list) else 0)
" 2>/dev/null || echo "0")

echo ""
echo "[Gitleaks] ======= SCAN SUMMARY ======="
echo "[Gitleaks] Secrets found: ${LEAK_COUNT}"
echo "[Gitleaks] Report: ${REPORT_DIR}/gitleaks-report.json"
echo "[Gitleaks] =============================="

if [ "$SCAN_EXIT" -ne 0 ] && [ "$LEAK_COUNT" -gt 0 ]; then
  echo ""
  echo "[Gitleaks] PIPELINE BLOCKED: ${LEAK_COUNT} secrets detected in repository!"
  echo "[Gitleaks] Remove secrets and rotate compromised credentials."
  exit 1
fi

echo "[Gitleaks] No secrets found."
