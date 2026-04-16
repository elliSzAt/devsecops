#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  SCA: Trivy Filesystem Scan"
echo "============================================"

REPORT_DIR="${REPORT_DIR:-./reports}"
WORKSPACE="${GITHUB_WORKSPACE:-.}"
APP_DIR="${WORKSPACE}/app"
TRIVY_VERSION="${TRIVY_VERSION:-0.58.0}"

mkdir -p "$REPORT_DIR"

if [ ! -d "${APP_DIR}/node_modules" ]; then
  echo "[SCA] WARNING: node_modules not found. Trivy will scan package.json/package-lock.json only."
fi

SCA_REPORT="${REPORT_DIR}/dependency-scan-report.json"

run_with_docker() {
  echo "[SCA] Running Trivy fs via Docker..."
  docker run --rm \
    -v "${APP_DIR}:/src:ro" \
    -v "$(cd "${REPORT_DIR}" && pwd):/output" \
    -v "${WORKSPACE}/.trivyignore:/root/.trivyignore:ro" \
    aquasec/trivy:${TRIVY_VERSION} \
    fs \
    --format json \
    --output /output/dependency-scan-report.json \
    --severity CRITICAL,HIGH \
    --ignorefile /root/.trivyignore \
    --scanners vuln \
    /src \
    || true
}

run_native() {
  echo "[SCA] Running Trivy fs native..."
  trivy fs \
    --format json \
    --output "${SCA_REPORT}" \
    --severity CRITICAL,HIGH \
    --scanners vuln \
    "${APP_DIR}" \
    || true
}

if command -v trivy &>/dev/null; then
  run_native
elif command -v docker &>/dev/null; then
  run_with_docker
else
  echo "[SCA] ERROR: Neither trivy nor docker found!"
  exit 1
fi

if [ ! -f "$SCA_REPORT" ]; then
  echo "[SCA] ERROR: No scan report found!"
  exit 1
fi

VULN_SUMMARY=$(python3 << PYEOF
import json, sys

with open("${SCA_REPORT}") as f:
    data = json.load(f)

critical = 0
high = 0
medium = 0
low = 0
total_vulns = 0

for r in data.get("Results", []):
    for v in r.get("Vulnerabilities", []):
        total_vulns += 1
        severity = v.get("Severity", "").upper()
        if severity == "CRITICAL":
            critical += 1
        elif severity == "HIGH":
            high += 1
        elif severity == "MEDIUM":
            medium += 1
        else:
            low += 1

print(f"{total_vulns} {critical} {high} {medium} {low}")
PYEOF
)

TOTAL=$(echo "$VULN_SUMMARY" | awk '{print $1}')
CRITICAL=$(echo "$VULN_SUMMARY" | awk '{print $2}')
HIGH=$(echo "$VULN_SUMMARY" | awk '{print $3}')
MEDIUM=$(echo "$VULN_SUMMARY" | awk '{print $4}')
LOW=$(echo "$VULN_SUMMARY" | awk '{print $5}')

echo ""
echo "[SCA] ========= DEPENDENCY SCAN SUMMARY ========="
echo "[SCA] Total vulnerabilities: ${TOTAL}"
echo "[SCA] ─────────────────────────────────────────────"
echo "[SCA] Critical:  ${CRITICAL}"
echo "[SCA] High:      ${HIGH}"
echo "[SCA] Medium:    ${MEDIUM}"
echo "[SCA] Low:       ${LOW}"
echo "[SCA] ─────────────────────────────────────────────"
echo "[SCA] Report: ${SCA_REPORT}"
echo "[SCA] ============================================="

if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
  echo ""
  echo "[SCA] PIPELINE BLOCKED: ${CRITICAL} Critical + ${HIGH} High vulnerabilities found!"
  echo "[SCA] Fix vulnerable dependencies before proceeding."
  exit 1
fi

echo "[SCA] Dependency scan passed - no High/Critical vulnerabilities."
