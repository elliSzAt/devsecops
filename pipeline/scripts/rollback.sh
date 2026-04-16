#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  ROLLBACK: Reverting to Previous Version"
echo "============================================"

COMPOSE_FILE="${DEPLOY_COMPOSE_FILE:-docker-compose.yml}"
CONTAINER_NAME="devsecops-app"
IMAGE_NAME="${IMAGE_NAME:-devsecops-app}"
PREVIOUS_IMAGE="${PREVIOUS_IMAGE:-}"
APP_PORT="${APP_PORT:-3000}"

# Determine rollback target
if [ -z "$PREVIOUS_IMAGE" ] || [ "$PREVIOUS_IMAGE" = "none" ]; then
  if [ -f /tmp/devsecops-previous-image.txt ]; then
    PREVIOUS_IMAGE=$(cat /tmp/devsecops-previous-image.txt)
  fi
fi

# If still no previous image, try the previous git commit
if [ -z "$PREVIOUS_IMAGE" ] || [ "$PREVIOUS_IMAGE" = "none" ]; then
  PREV_SHA=$(git rev-parse HEAD~1 2>/dev/null | cut -c1-7 || echo "")
  if [ -n "$PREV_SHA" ]; then
    PREVIOUS_IMAGE="${IMAGE_NAME}:${PREV_SHA}"
    echo "[Rollback] Using previous commit image: ${PREVIOUS_IMAGE}"
  else
    echo "[Rollback] ERROR: No previous version available for rollback!"
    echo "[Rollback] Manual intervention required."
    exit 1
  fi
fi

echo "[Rollback] Rolling back to: ${PREVIOUS_IMAGE}"

# Verify the previous image exists
if ! docker image inspect "$PREVIOUS_IMAGE" &>/dev/null; then
  echo "[Rollback] WARNING: Previous image not found locally."
  echo "[Rollback] Attempting to pull from registry..."
  REGISTRY="${REGISTRY:-localhost:5000}"
  docker pull "${REGISTRY}/${PREVIOUS_IMAGE}" 2>/dev/null && \
    docker tag "${REGISTRY}/${PREVIOUS_IMAGE}" "${PREVIOUS_IMAGE}" || {
    echo "[Rollback] ERROR: Cannot find previous image anywhere!"
    echo "[Rollback] Manual intervention required."
    exit 1
  }
fi

# Stop current deployment
echo "[Rollback] Stopping current deployment..."
docker compose -f "${COMPOSE_FILE}" down --timeout 10 2>/dev/null || true
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

# Re-tag previous image and redeploy
echo "[Rollback] Deploying previous version..."
docker tag "${PREVIOUS_IMAGE}" "${IMAGE_NAME}:latest"
docker compose -f "${COMPOSE_FILE}" up -d app

# Wait and verify
echo "[Rollback] Verifying rollback..."
for i in $(seq 1 15); do
  if curl -sf "http://localhost:${APP_PORT}" > /dev/null 2>&1; then
    echo ""
    echo "[Rollback] ======= ROLLBACK SUCCESSFUL ======="
    echo "[Rollback] Reverted to: ${PREVIOUS_IMAGE}"
    echo "[Rollback] Application is responding."
    echo "[Rollback] ======================================"
    echo ""
    echo "[Rollback] ACTION REQUIRED:"
    echo "[Rollback]   1. Check DAST report for vulnerability details"
    echo "[Rollback]   2. Fix identified issues in source code"
    echo "[Rollback]   3. Push a new commit to re-trigger the pipeline"
    exit 0
  fi
  echo "[Rollback] Waiting for app... (attempt $i/15)"
  sleep 4
done

echo "[Rollback] ERROR: Rollback deployment also failed!"
echo "[Rollback] CRITICAL: Manual intervention required!"
exit 1
