#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  SCA: OWASP Dependency-Check"
echo "============================================"

REPORT_DIR="${REPORT_DIR:-./reports}"
WORKSPACE="${GITHUB_WORKSPACE:-.}"
APP_DIR="${WORKSPACE}/app"
DC_DATA_DIR="${DC_DATA_DIR:-/tmp/dependency-check-data}"

mkdir -p "$REPORT_DIR"
mkdir -p "$DC_DATA_DIR"

if [ ! -d "${APP_DIR}/node_modules" ]; then
  echo "[SCA] ERROR: node_modules not found! Run 'npm ci' first."
  exit 1
fi

NODE_MODULES_SIZE=$(du -sh "${APP_DIR}/node_modules" 2>/dev/null | awk '{print $1}')
echo "[SCA] Scan target: ${APP_DIR}/node_modules (${NODE_MODULES_SIZE})"

run_with_docker() {
  echo "[SCA] Running OWASP Dependency-Check via Docker..."
  docker run --rm \
    -v "${APP_DIR}:/src:ro" \
    -v "$(cd "${REPORT_DIR}" && pwd):/report" \
    owasp/dependency-check-action:11.0.0 \
    --scan /src \
    --format JSON \
    --format HTML \
    --out /report \
    --project "devsecops-app" \
    --disableAssembly \
    --nodeAuditSkipDevDependencies \
    --noupdate \
    || true
}

run_native() {
  echo "[SCA] Running OWASP Dependency-Check native..."
  dependency-check.sh \
    --scan "${APP_DIR}" \
    --format JSON \
    --format HTML \
    --out "${REPORT_DIR}" \
    --project "devsecops-app" \
    --disableAssembly \
    --nodeAuditSkipDevDependencies \
    --nvdApiKey "${NVD_API_KEY:-}" \
    || true
}

if command -v dependency-check.sh &>/dev/null; then
  run_native
elif command -v docker &>/dev/null; then
  run_with_docker
else
  echo "[SCA] ERROR: Neither dependency-check nor docker found!"
  exit 1
fi

DC_REPORT="${REPORT_DIR}/dependency-check-report.json"

if [ ! -f "$DC_REPORT" ]; then
  echo "[SCA] WARNING: Report not generated, checking alternative names..."
  for f in "${REPORT_DIR}"/*dependency-check*.json; do
    if [ -f "$f" ]; then
      DC_REPORT="$f"
      break
    fi
  done
fi

if [ ! -f "$DC_REPORT" ]; then
  echo "[SCA] ERROR: No Dependency-Check report found!"
  echo "[SCA] Pipeline FAILED - cannot verify dependencies are safe."
  exit 1
fi

VULN_SUMMARY=$(python3 << PYEOF
import json, sys

with open("${DC_REPORT}") as f:
    data = json.load(f)

critical = 0
high = 0
medium = 0
low = 0
total_deps = len(data.get("dependencies", []))
vuln_deps = 0

for dep in data.get("dependencies", []):
    vulns = dep.get("vulnerabilities", [])
    if vulns:
        vuln_deps += 1
    for v in vulns:
        severity = v.get("severity", "").upper()
        if severity == "CRITICAL":
            critical += 1
        elif severity == "HIGH":
            high += 1
        elif severity == "MEDIUM":
            medium += 1
        else:
            low += 1

print(f"{total_deps} {vuln_deps} {critical} {high} {medium} {low}")
PYEOF
)

TOTAL_DEPS=$(echo "$VULN_SUMMARY" | awk '{print $1}')
VULN_DEPS=$(echo "$VULN_SUMMARY" | awk '{print $2}')
CRITICAL=$(echo "$VULN_SUMMARY" | awk '{print $3}')
HIGH=$(echo "$VULN_SUMMARY" | awk '{print $4}')
MEDIUM=$(echo "$VULN_SUMMARY" | awk '{print $5}')
LOW=$(echo "$VULN_SUMMARY" | awk '{print $6}')

echo ""
echo "[SCA] ========= DEPENDENCY-CHECK SUMMARY ========="
echo "[SCA] Total dependencies scanned: ${TOTAL_DEPS}"
echo "[SCA] Vulnerable dependencies:    ${VULN_DEPS}"
echo "[SCA] ─────────────────────────────────────────────"
echo "[SCA] Critical:  ${CRITICAL}"
echo "[SCA] High:      ${HIGH}"
echo "[SCA] Medium:    ${MEDIUM}"
echo "[SCA] Low:       ${LOW}"
echo "[SCA] ─────────────────────────────────────────────"
echo "[SCA] Report JSON: ${DC_REPORT}"
echo "[SCA] Report HTML: ${REPORT_DIR}/dependency-check-report.html"
echo "[SCA] ============================================="

if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
  echo ""
  echo "[SCA] PIPELINE BLOCKED: ${CRITICAL} Critical + ${HIGH} High vulnerabilities found!"
  echo "[SCA] Fix vulnerable dependencies before proceeding."
  exit 1
fi

echo "[SCA] Dependency scan passed - no High/Critical vulnerabilities."
