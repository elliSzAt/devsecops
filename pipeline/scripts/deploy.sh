#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  Deploy Application"
echo "============================================"

IMAGE_NAME="${IMAGE_NAME:-devsecops-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
COMPOSE_FILE="${DEPLOY_COMPOSE_FILE:-docker-compose.yml}"
CONTAINER_NAME="devsecops-app"
APP_PORT="${APP_PORT:-3000}"

echo "[Deploy] Image:     ${IMAGE_NAME}:${IMAGE_TAG}"
echo "[Deploy] Compose:   ${COMPOSE_FILE}"
echo "[Deploy] Container: ${CONTAINER_NAME}"

# Save current state for potential rollback
PREVIOUS_IMAGE=$(docker inspect "${CONTAINER_NAME}" --format='{{.Config.Image}}' 2>/dev/null || echo "none")
echo "[Deploy] Previous image: ${PREVIOUS_IMAGE}"
echo "${PREVIOUS_IMAGE}" > /tmp/devsecops-previous-image.txt

# Stop existing deployment gracefully
echo "[Deploy] Stopping existing deployment..."
docker compose -f "${COMPOSE_FILE}" down --timeout 30 2>/dev/null || true

# Deploy new version
echo "[Deploy] Starting new deployment..."
export IMAGE_TAG
docker compose -f "${COMPOSE_FILE}" up -d app

# Wait for container to be running
echo "[Deploy] Waiting for container to start..."
for i in $(seq 1 20); do
  STATUS=$(docker inspect "${CONTAINER_NAME}" --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
  if [ "$STATUS" = "running" ]; then
    echo "[Deploy] Container is running."
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "[Deploy] ERROR: Container failed to start after 40s!"
    exit 1
  fi
  sleep 2
done

# Wait for health check
echo "[Deploy] Running health checks..."
for i in $(seq 1 15); do
  HEALTH=$(docker inspect "${CONTAINER_NAME}" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
  if [ "$HEALTH" = "healthy" ]; then
    echo "[Deploy] Application is healthy!"
    exit 0
  fi
  if [ "$HEALTH" = "unhealthy" ]; then
    echo "[Deploy] ERROR: Application is unhealthy!"
    docker logs "${CONTAINER_NAME}" --tail 20
    exit 1
  fi
  echo "[Deploy] Health: ${HEALTH} (attempt $i/15)..."
  sleep 4
done

echo "[Deploy] WARNING: Health check timed out, verifying with HTTP..."
if curl -sf "http://localhost:${APP_PORT}" > /dev/null 2>&1; then
  echo "[Deploy] Application responds to HTTP - deploy successful."
else
  echo "[Deploy] ERROR: Application not responding!"
  exit 1
fi
