#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  SAST: Semgrep - Code Scanning"
echo "============================================"

REPORT_DIR="${REPORT_DIR:-./reports}"
WORKSPACE="${GITHUB_WORKSPACE:-.}"
SEMGREP_RULES="${WORKSPACE}/security/semgrep/.semgrep.yml"
SCAN_EXIT=0

mkdir -p "$REPORT_DIR"

SEMGREP_ARGS=(
  --json
  --output "${REPORT_DIR}/sast-report.json"
)

if [ -f "$SEMGREP_RULES" ]; then
  SEMGREP_ARGS+=(--config "$SEMGREP_RULES")
fi
SEMGREP_ARGS+=(--config "p/ci" --metrics=off)

run_with_docker() {
  echo "[Semgrep] Running via Docker..."
  docker run --rm \
    -v "${WORKSPACE}:/src" \
    --entrypoint semgrep \
    semgrep/semgrep:1.90.0 \
    scan \
    --config "/src/security/semgrep/.semgrep.yml" \
    --config "p/ci" \
    --metrics=off \
    --json \
    --output "/src/${REPORT_DIR}/sast-report.json" \
    /src/app/src/ \
    || SCAN_EXIT=$?
}

run_native() {
  echo "[Semgrep] Running native binary..."
  semgrep scan \
    "${SEMGREP_ARGS[@]}" \
    "${WORKSPACE}/app/src/" \
    || SCAN_EXIT=$?
}

if command -v semgrep &>/dev/null; then
  run_native
elif command -v docker &>/dev/null; then
  run_with_docker
else
  echo "[Semgrep] ERROR: Neither semgrep nor docker found!"
  exit 1
fi

if [ ! -f "${REPORT_DIR}/sast-report.json" ]; then
  echo "[Semgrep] ERROR: No scan report generated!"
  exit 1
fi

# Semgrep severity: ERROR = Critical/High, WARNING = Medium, INFO = Low
FINDINGS=$(python3 << PYEOF
import json

with open("${REPORT_DIR}/sast-report.json") as f:
    data = json.load(f)

results = data.get("results", [])
errors = [r for r in results if r.get("extra", {}).get("severity", "") == "ERROR"]
warnings = [r for r in results if r.get("extra", {}).get("severity", "") == "WARNING"]
infos = [r for r in results if r.get("extra", {}).get("severity", "") == "INFO"]

print(f"{len(results)} {len(errors)} {len(warnings)} {len(infos)}")
PYEOF
)

TOTAL=$(echo "$FINDINGS" | awk '{print $1}')
ERRORS=$(echo "$FINDINGS" | awk '{print $2}')
WARNINGS=$(echo "$FINDINGS" | awk '{print $3}')
INFOS=$(echo "$FINDINGS" | awk '{print $4}')

echo ""
echo "[Semgrep] ======= SAST SCAN SUMMARY ======="
echo "[Semgrep] Total findings:    ${TOTAL}"
echo "[Semgrep] High/Critical:     ${ERRORS}"
echo "[Semgrep] Medium (warnings): ${WARNINGS}"
echo "[Semgrep] Low (info):        ${INFOS}"
echo "[Semgrep] Report: ${REPORT_DIR}/sast-report.json"
echo "[Semgrep] ======================================"

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "[Semgrep] PIPELINE BLOCKED: ${ERRORS} High/Critical findings detected!"
  echo "[Semgrep] Fix security issues before proceeding."
  exit 1
fi

echo "[Semgrep] SAST scan passed - no High/Critical findings."
