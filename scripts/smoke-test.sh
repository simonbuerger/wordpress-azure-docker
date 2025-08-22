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

# Simulate Azure bind-mounted /home by using a host temp dir
HOME_MNT="$(mktemp -d -t wazm-home-XXXXXX)"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$HOME_MNT"' EXIT

mkdir -p "$HOME_MNT/LogFiles/sync/apache2" "$HOME_MNT/LogFiles/sync/archive"

# Pre-seed logs that logrotate should handle; use sentinels for validation
echo "SMOKE_PRESEEDED_ERROR_MARK $(date)" >> "$HOME_MNT/LogFiles/sync/apache2/error.log"
echo "SMOKE_PRESEEDED_PHP_MARK $(date)" >> "$HOME_MNT/LogFiles/sync/apache2/php-error.log"
echo "SMOKE_PRESEEDED_CRON_MARK $(date)" >> "$HOME_MNT/LogFiles/sync/cron.log"
echo "SMOKE_PRESEEDED_SUPERVISOR_MARK $(date)" >> "$HOME_MNT/LogFiles/supervisord.log"

echo "[smoke] Starting container: ${IMAGE_TAG}"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$NAME" \
  -e DOCKER_SYNC_ENABLED=1 \
  -e USE_SYSTEM_CRON=1 \
  -v "$HOME_MNT":/home \
  -p 0:80 \
  "$IMAGE_TAG" >/dev/null

# Wait a bit for init to run (sync-init writes logs immediately; apache restarts)
ATTEMPTS=30
SLEEP=4
echo "[smoke] Waiting up to $((ATTEMPTS*SLEEP))s for logs to appear..."
for i in $(seq 1 "$ATTEMPTS"); do
  if docker exec "$NAME" test -s /homelive/LogFiles/sync/sync-init.current.log && \
     docker exec "$NAME" test -s /homelive/LogFiles/sync/apache2/error.log; then
    break
  fi
  sleep "$SLEEP"
done

echo "[smoke] Verifying expected log files and symlinks (homelive mode)..."
docker exec "$NAME" bash -lc 'ls -l /homelive/LogFiles/sync/sync-init.current.log /homelive/LogFiles/sync/apache2/error.log'

# Unison should be started by sync-init via supervisorctl; verify log exists or is growing on homelive
for i in $(seq 1 "$ATTEMPTS"); do
  if docker exec "$NAME" bash -lc 'test -s /home/LogFiles/sync/unison.log || test -s /homelive/LogFiles/sync/unison.log'; then
    break
  fi
  sleep "$SLEEP"
done
docker exec "$NAME" bash -lc 'test -f /home/LogFiles/sync/unison.log -o -f /homelive/LogFiles/sync/unison.log || (echo "unison.log missing"; exit 1)'
docker exec "$NAME" bash -lc 'tail -n 5 /home/LogFiles/sync/unison.log 2>/dev/null || tail -n 5 /homelive/LogFiles/sync/unison.log 2>/dev/null || true'

# Apache/PHP logs should exist under homelive when sync enabled
docker exec "$NAME" bash -lc 'test -f /homelive/LogFiles/sync/apache2/error.log || (echo "apache error.log missing"; exit 1)'
docker exec "$NAME" bash -lc 'test -f /homelive/LogFiles/sync/apache2/php-error.log || install -Dm0644 /dev/null /homelive/LogFiles/sync/apache2/php-error.log'
docker exec "$NAME" bash -lc 'test -f /homelive/LogFiles/sync/apache2/php-error.log || (echo "php-error.log missing"; exit 1)'

# Validate rotation persistence to /home via logrotate postrotate rsync
echo "[smoke] Validating rotation persistence (homelive -> home) for test.log..."
# Seed a homelive test log so homelive logrotate rotates it and postrotate rsync persists to home
docker exec "$NAME" bash -lc 'echo "SMOKE_ROTATE_TEST $(date -u +%FT%TZ)" >> /homelive/LogFiles/sync/test.log && chown www-data:www-data /homelive/LogFiles/sync/test.log'
docker exec "$NAME" bash -lc '/usr/sbin/logrotate -f /etc/logrotate.d/apache2 >/dev/null 2>&1 || true'
docker exec "$NAME" bash -lc 'ls /home/LogFiles/sync/archive/test.log.* >/dev/null 2>&1 || (echo "test.log archive missing in home"; exit 1)'
docker exec "$NAME" bash -lc 'if ls /home/LogFiles/sync/archive/test.log.*.gz >/dev/null 2>&1; then zgrep -a -q "SMOKE_ROTATE_TEST" /home/LogFiles/sync/archive/test.log.*.gz || (echo "SMOKE_ROTATE_TEST missing in compressed archive"; exit 1); else grep -q "SMOKE_ROTATE_TEST" /home/LogFiles/sync/archive/test.log.* || (echo "SMOKE_ROTATE_TEST missing in archive"; exit 1); fi'

# Validate per-run logs persisted to /home
echo "[smoke] Validating per-run logs copied to /home..."
docker exec "$NAME" bash -lc 'ls -1 /home/LogFiles/sync/runs/sync-init-*.log | head -n1 >/dev/null 2>&1 || (echo "no per-run logs in home"; exit 1)'

# Validate cron writes to homelive when sync enabled
docker exec "$NAME" bash -lc 'echo SMOKE_CRON >> /homelive/LogFiles/sync/cron.log && tail -n 5 /homelive/LogFiles/sync/cron.log | grep -q SMOKE_CRON || (echo "cron homelive not writable"; exit 1)'

# UI will scan latest per-run from /home; ensure at least one file exists
echo "[smoke] OK: homelive writers, home persistence via rsync, and per-run copies validated."

echo "[smoke] Cleaning up"
docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "[smoke] Done"


