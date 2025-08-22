#!/usr/bin/env bash
set -euo pipefail

# Basic end-to-end smoke test for logging and sync wiring.
# Usage:
#   scripts/smoke-test.sh <image-tag>
# Example:
#   scripts/smoke-test.sh bluegrassdigital/wordpress-azure-sync:8.4-latest

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <image-tag>"
  exit 2
fi

IMAGE_TAG="$1"
NAME="wazm-smoke-$$"

echo "[smoke] Starting container: ${IMAGE_TAG}"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$NAME" \
  -e DOCKER_SYNC_ENABLED=1 \
  -e USE_SYSTEM_CRON=1 \
  -p 0:80 \
  "$IMAGE_TAG" >/dev/null

# Wait a bit for init to run (sync-init writes logs immediately; apache restarts)
ATTEMPTS=30
SLEEP=4
echo "[smoke] Waiting up to $((ATTEMPTS*SLEEP))s for logs to appear..."
for i in $(seq 1 "$ATTEMPTS"); do
  if docker exec "$NAME" test -s /home/LogFiles/sync-init.log && \
     docker exec "$NAME" test -s /home/LogFiles/sync/sync-init.current.log && \
     docker exec "$NAME" test -L /homelive/LogFiles/sync-init.log && \
     docker exec "$NAME" test -s /home/LogFiles/sync/apache2/error.log; then
    break
  fi
  sleep "$SLEEP"
done

echo "[smoke] Verifying expected log files and symlinks..."
docker exec "$NAME" bash -lc 'ls -l /home/LogFiles/sync-init.log /home/LogFiles/sync/sync-init.current.log /homelive/LogFiles/sync-init.log'

# Unison should be started by sync-init via supervisorctl; verify log exists or is growing
docker exec "$NAME" bash -lc 'test -f /home/LogFiles/sync/unison.log && tail -n 5 /home/LogFiles/sync/unison.log || (echo "unison.log not found"; exit 1)'

# Apache/PHP logs should exist
docker exec "$NAME" bash -lc 'test -s /home/LogFiles/sync/apache2/error.log || (echo "apache error.log empty"; exit 1)'

echo "[smoke] OK: core logs present (sync-init, unison, apache error)."

echo "[smoke] Cleaning up"
docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "[smoke] Done"


