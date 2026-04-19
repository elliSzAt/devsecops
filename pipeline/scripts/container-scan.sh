#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  Container Scan (Trivy Image)"
echo "============================================"

REPORT_DIR="${REPORT_DIR:-./reports}"
IMAGE_NAME="${IMAGE_NAME:-devsecops-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
SCAN_EXIT=0

mkdir -p "$REPORT_DIR"

echo "[Trivy] Scanning image: ${FULL_IMAGE}"

WORKSPACE="${GITHUB_WORKSPACE:-.}"
TRIVY_IGNOREFILE="${WORKSPACE}/.trivyignore"
TRIVY_CONFIG="${WORKSPACE}/trivy.yaml"

TRIVY_EXTRA_ARGS=""
if [ -f "$TRIVY_CONFIG" ]; then
  TRIVY_EXTRA_ARGS="--config ${TRIVY_CONFIG}"
  echo "[Trivy] Using config: ${TRIVY_CONFIG}"
fi
if [ -f "$TRIVY_IGNOREFILE" ]; then
  TRIVY_EXTRA_ARGS="${TRIVY_EXTRA_ARGS} --ignorefile ${TRIVY_IGNOREFILE}"
  echo "[Trivy] Using ignorefile: ${TRIVY_IGNOREFILE}"
fi

run_trivy_docker() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/${REPORT_DIR}:/output" \
    -v "$(pwd)/.trivyignore:/root/.trivyignore:ro" \
    -v "$(pwd)/trivy.yaml:/root/trivy.yaml:ro" \
    aquasec/trivy:0.62.1 \
    image \
    --skip-policy-update \
    --format json \
    --output "/output/container-scan-report.json" \
    --severity CRITICAL,HIGH \
    --ignorefile /root/.trivyignore \
    --ignore-unfixed \
    --scanners vuln \
    "${FULL_IMAGE}" \
    || SCAN_EXIT=$?
}

run_trivy_native() {
  trivy image \
    --skip-policy-update \
    --format json \
    --output "${REPORT_DIR}/container-scan-report.json" \
    --severity CRITICAL,HIGH,MEDIUM \
    ${TRIVY_EXTRA_ARGS} \
    "${FULL_IMAGE}" \
    || SCAN_EXIT=$?
}

if command -v trivy &>/dev/null; then
  run_trivy_native
elif command -v docker &>/dev/null; then
  run_trivy_docker
else
  echo "[Trivy] ERROR: Neither trivy nor docker found!"
  exit 1
fi

if [ ! -f "${REPORT_DIR}/container-scan-report.json" ]; then
  echo "[Trivy] ERROR: No scan report generated!"
  exit 1
fi

SUMMARY=$(python3 << PYEOF
import json

with open("${REPORT_DIR}/container-scan-report.json") as f:
    data = json.load(f)

c = h = m = mis = 0
for result in data.get("Results", []):
    for vuln in result.get("Vulnerabilities", []):
        sev = vuln.get("Severity", "").upper()
        if sev == "CRITICAL": c += 1
        elif sev == "HIGH": h += 1
        elif sev == "MEDIUM": m += 1
    mis += len(result.get("Misconfigurations", []))

print(f"{c} {h} {m} {mis}")
PYEOF
)

CRITICAL=$(echo "$SUMMARY" | awk '{print $1}')
HIGH=$(echo "$SUMMARY" | awk '{print $2}')
MEDIUM=$(echo "$SUMMARY" | awk '{print $3}')
MISCONF=$(echo "$SUMMARY" | awk '{print $4}')

echo ""
echo "[Trivy] ======= IMAGE SCAN SUMMARY ======="
echo "[Trivy] Image:             ${FULL_IMAGE}"
echo "[Trivy] Critical:          ${CRITICAL}"
echo "[Trivy] High:              ${HIGH}"
echo "[Trivy] Medium:            ${MEDIUM}"
echo "[Trivy] Misconfigurations: ${MISCONF}"
echo "[Trivy] Report: ${REPORT_DIR}/container-scan-report.json"
echo "[Trivy] ======================================"

if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
  echo ""
  echo "[Trivy] PIPELINE BLOCKED: ${CRITICAL} Critical + ${HIGH} High vulnerabilities in image!"
  echo "[Trivy] Fix base image or vulnerable packages before pushing."
  exit 1
fi

echo "[Trivy] Container scan passed - no High/Critical vulnerabilities."
