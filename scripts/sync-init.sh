#!/usr/bin/env bash

# Per-run logging: capture the entire run to unique files under /home/LogFiles/sync
RUN_TS=$(date +%Y%m%d-%H%M%S)
LOG_BASE_DIR=/home/LogFiles/sync
RUNS_DIR="$LOG_BASE_DIR/runs"
mkdir -p "$RUNS_DIR"
RUN_LOG="$RUNS_DIR/sync-init-$RUN_TS.log"
ERR_LOG="$RUNS_DIR/sync-init-error-$RUN_TS.log"
# Redirect all stdout/stderr to the per-run logs (and echo to console for supervisor)
exec > >(tee -a "$RUN_LOG") 2> >(tee -a "$ERR_LOG" >&2)
# Update convenient symlinks to the current run
ln -sfn "$RUN_LOG" "$LOG_BASE_DIR/sync-init.current.log"
ln -sfn "$ERR_LOG" "$LOG_BASE_DIR/sync-init-error.current.log"
# Back-compat symlinks for existing consumers (plugin/configs)
ln -sfn "$LOG_BASE_DIR/sync-init.current.log" /home/LogFiles/sync-init.log
ln -sfn "$LOG_BASE_DIR/sync-init-error.current.log" /home/LogFiles/sync-init-error.log

# This script bootstraps and synchronizes WordPress between persistent storage (/home)
# and the live working tree (/homelive).
#
# High-level flow:
# - Prepare wp-content directories and ensure /homelive/wp-content/uploads points to
#   /home/wp-content/uploads so uploads persist across deployments.
# - When DOCKER_SYNC_ENABLED is unset: operate directly from /home (no Unison), set up cron.
# - When DOCKER_SYNC_ENABLED is set:
#   - Ensure WordPress core and wp-config exist in /home
#   - Seed /homelive from /home (code, content, logs)
#   - To avoid rsync races on active logs, force a logrotate to snapshot files first
#   - Rewrite Apache/PHP config paths from /home to /homelive
#   - Start Unison to keep /homelive authoritative going forward
#   - Install crons for WP scheduled events and daily log rotation

WP_CONTENT_ROOT_LIVE=$(echo $WP_CONTENT_ROOT | sed -e "s/\/home\//\/homelive\//g")
mkdir -p "$WP_CONTENT_ROOT/uploads"
mkdir -p "$WP_CONTENT_ROOT_LIVE"

# Lightweight logging helpers
log_info() { echo "$(date) [INFO] $*"; }
log_warn() { echo "$(date) [WARN] $*"; }
log_error() { echo "$(date) [ERROR] $*"; }

log_info "Init starting. DOCKER_SYNC_ENABLED='${DOCKER_SYNC_ENABLED:-}' USE_SYSTEM_CRON='${USE_SYSTEM_CRON:-1}'"
log_info "Paths: WP_CONTENT_ROOT='$WP_CONTENT_ROOT' WP_CONTENT_ROOT_LIVE='$WP_CONTENT_ROOT_LIVE' APACHE_DOCUMENT_ROOT='${APACHE_DOCUMENT_ROOT}' APACHE_SITE_ROOT='${APACHE_SITE_ROOT}' APACHE_LOG_DIR='${APACHE_LOG_DIR}'"

# Helper to ensure a symlink points to the intended target. If a real directory
# or wrong symlink exists at the link path, it will be replaced with the symlink.
ensure_symlink() {
    local target="$1"
    local link="$2"
    echo "$(date) ensure_symlink: link='$link' target='$target'"
    if [[ -e "$link" || -L "$link" ]]; then
        if [[ -L "$link" ]]; then
            local current_target
            current_target="$(readlink -f "$link" || true)"
            local resolved_target
            resolved_target="$(readlink -f "$target" || true)"
            if [[ "$current_target" != "$resolved_target" || -z "$current_target" ]]; then
                echo "$(date) ensure_symlink: replacing incorrect/broken symlink ('$current_target') with '$target'"
                rm -f "$link" 2>/dev/null || true
                ln -s "$target" "$link" || true
            else
                echo "$(date) ensure_symlink: symlink already correct"
            fi
        else
            echo "$(date) ensure_symlink: replacing existing file/dir at '$link' with symlink to '$target'"
            rm -rf "$link" 2>/dev/null || true
            ln -s "$target" "$link" || true
        fi
    else
        echo "$(date) ensure_symlink: creating symlink '$link' -> '$target'"
        ln -s "$target" "$link" || true
    fi
}

# Ensure uploads symlink exists in live path and points to persisted /home path
ensure_symlink "$WP_CONTENT_ROOT/uploads" "$WP_CONTENT_ROOT_LIVE/uploads"

if [[ -z "${DOCKER_SYNC_ENABLED}" ]]; then
cat >/home/syncstatus <<EOL
Sync disabled
EOL
log_info "Sync disabled - init start"
echo "cd /home" >> /root/.bashrc

if [[ "${USE_SYSTEM_CRON:-1}" == "1" || "${USE_SYSTEM_CRON:-1}" == "true" ]]; then
  log_info "Installing WP cron (every 10m) for /home path"
  (crontab -l 2>/dev/null; echo "*/10 * * * * . /etc/profile; (/bin/date && cd /home/site/wwwroot && /usr/local/bin/wp --allow-root cron event run --due-now) | grep -v \"Warning:\" >> /home/LogFiles/sync/cron.log  2>&1") | crontab
fi

(crontab -l 2>/dev/null; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/apache2 > /dev/null") | crontab
log_info "Installed daily logrotate cron for /etc/logrotate.d/apache2"

# Bootstrap WordPress core in /home if missing
if [[ ! -f "/home/site/wwwroot/index.php" ]]; then
    echo "$(date) Bootstrapping WordPress core in /home/site/wwwroot"
    ( cd /home/site/wwwroot && /usr/local/bin/wp --allow-root core download ) || echo "$(date) WP core download skipped/failed"
fi

# Auto-create wp-config.php if missing using container env (no DB check)
if [[ ! -f "/home/site/wwwroot/wp-config.php" ]]; then
    echo "$(date) Creating wp-config.php from docker template"
    if [[ -f "/usr/src/wordpress/wp-config-docker.php" ]]; then
        cp /usr/src/wordpress/wp-config-docker.php /home/site/wwwroot/wp-config.php || true
    else
        DB_NAME=${DB_DATABASE:-wordpress}
        DB_USER=${DB_USERNAME:-wordpress}
        DB_PASS=${DB_PASSWORD:-wordpress}
        DB_HOST=${DB_HOST:-db}
        ( cd /home/site/wwwroot && /usr/local/bin/wp --allow-root config create --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="$DB_HOST" --skip-check --force ) || echo "$(date) wp-config creation skipped/failed"
    fi
    # Generate unique salts for this installation
    ( cd /home/site/wwwroot && /usr/local/bin/wp --allow-root config shuffle-salts ) || echo "$(date) shuffle-salts skipped/failed"
fi

echo "$(date) Sync disabled - init complete"

# Ensure bundled plugin exists and optionally auto-activate (sync disabled path)
if [[ -d "/opt/wordpress-azure-monitor" ]]; then
    mkdir -p /home/site/wwwroot/wp-content/plugins
    rsync -a /opt/wordpress-azure-monitor/ /home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor/ || true
fi
if [[ -n "${WAZM_AUTO_ACTIVATE}" && "${WAZM_AUTO_ACTIVATE}" == "1" ]]; then
    WP_CLI_ALLOW_ROOT=1 sh -lc "cd '/home/site/wwwroot' && wp core is-installed --quiet && wp plugin activate wordpress-azure-monitor --quiet" || true
fi
else
SECONDS=0
log_info "Sync enabled - init start"

rm -rf /home/syncstatus

echo "cd /homelive" >> /root/.bashrc

log_info "Starting unison flow from /home to /homelive"

find . -type d -name '*.unison.tmp' -exec rm -rf {} +

# unison default -perms -1 -force /home -dontchmod=false

echo "$(date) wp content Folders: $WP_CONTENT_ROOT $WP_CONTENT_ROOT_LIVE"

mkdir -p /homelive/LogFiles/sync/apache2
mkdir -p /homelive/LogFiles/sync/archive

WP_OWNER=www-data # <-- wordpress owner
WP_GROUP=www-data # <-- wordpress group

# Bootstrap WordPress core in /home if missing before initial rsync
if [[ ! -f "/home/site/wwwroot/index.php" ]]; then
	echo "$(date) Bootstrapping WordPress core in /home/site/wwwroot"
	( cd /home/site/wwwroot && /usr/local/bin/wp --allow-root core download ) || echo "$(date) WP core download skipped/failed"
fi

# Auto-create wp-config.php if missing using container env (no DB check)
if [[ ! -f "/home/site/wwwroot/wp-config.php" ]]; then
	echo "$(date) Creating wp-config.php from docker template"
	if [[ -f "/usr/src/wordpress/wp-config-docker.php" ]]; then
		cp /usr/src/wordpress/wp-config-docker.php /home/site/wwwroot/wp-config.php || true
	else
		# Fallback to wp-cli if template missing
		DB_NAME=${DB_DATABASE:-wordpress}
		DB_USER=${DB_USERNAME:-wordpress}
		DB_PASS=${DB_PASSWORD:-wordpress}
		DB_HOST=${DB_HOST:-db}
		( cd /home/site/wwwroot && /usr/local/bin/wp --allow-root config create --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="$DB_HOST" --skip-check --force ) || echo "$(date) wp-config creation skipped/failed"
	fi
    # Generate unique salts for this installation
    ( cd /home/site/wwwroot && /usr/local/bin/wp --allow-root config shuffle-salts ) || echo "$(date) shuffle-salts skipped/failed"
fi

# Ensure target exists
mkdir -p /homelive/site/wwwroot

# Rotate logs to snapshot active files before seeding to /homelive.
# This avoids rsync 'vanished file' warnings during active writes.
echo "$(date) Rotating logs to snapshot active files before seeding"
if logrotate -f /etc/logrotate.d/apache2 >/dev/null 2>&1; then
  echo "$(date) Log rotation forced successfully"
else
  echo "$(date) Log rotation failed (continuing)"
fi

echo "$(date) Seeding code: /home/site/wwwroot -> /homelive/site/wwwroot"
if rsync -apoghW --no-compress /home/site/wwwroot/ /homelive/site/wwwroot/ --exclude 'wp-content' --exclude '*.unison.tmp' --chown "$WP_OWNER:$WP_GROUP" --chmod "D0755,F0644"; then
  echo "$(date) Seeded code OK"
else
  echo "$(date) Seed code FAILED (non-fatal)"
fi

echo "$(date) Seeding wp-content (excluding uploads): $WP_CONTENT_ROOT -> $WP_CONTENT_ROOT_LIVE"
if rsync -apoghW --no-compress "$WP_CONTENT_ROOT/" "$WP_CONTENT_ROOT_LIVE/" --exclude 'uploads' --exclude '*.unison.tmp' --chown "$WP_OWNER:$WP_GROUP" --chmod "D0775,F0664"; then
  echo "$(date) Seeded wp-content OK"
else
  echo "$(date) Seed wp-content FAILED (non-fatal)"
fi

echo "$(date) Seeding logs: /home/LogFiles -> /homelive/LogFiles (excluding sync/runs)"
if rsync -apoghW --no-compress /home/LogFiles/ /homelive/LogFiles/ --exclude '*.unison.tmp' --exclude 'sync/runs/**'; then
  echo "$(date) Seeded logs OK"
else
  echo "$(date) Seed logs FAILED (non-fatal)"
fi
log_info "Fixing directory permissions for '$APACHE_DOCUMENT_ROOT_LIVE'"

APACHE_DOCUMENT_ROOT_LIVE=$(echo $APACHE_DOCUMENT_ROOT | sed -e "s/\/home\//\/homelive\//g")

if fix-wordpress-permissions.sh $APACHE_DOCUMENT_ROOT_LIVE; then
  log_info "Permissions fixed"
else
  log_warn "Permission fix script failed (continuing)"
fi

log_info "Updating Apache/PHP configs to point to homelive rather than home"

# Re-ensure uploads symlink even if WP created a real folder; replace incorrect links
ensure_symlink "$WP_CONTENT_ROOT/uploads" "$WP_CONTENT_ROOT_LIVE/uploads"

APACHE_SITE_ROOT_LIVE=$(echo $APACHE_SITE_ROOT | sed -e "s/\/home\//\/homelive\//g")
APACHE_LOG_DIR_LIVE=$(echo $APACHE_LOG_DIR | sed -e "s/\/home\//\/homelive\//g")
APACHE_SITE_ROOT_LIVE_ESC=$(sed 's/[\*\.^\//]/\\&/g' <<<"$APACHE_SITE_ROOT_LIVE")
APACHE_DOCUMENT_ROOT_LIVE_ESC=$(sed 's/[\*\.^\//]/\\&/g' <<<"$APACHE_DOCUMENT_ROOT_LIVE")
APACHE_LOG_DIR_LIVE_ESC=$(sed 's/[\*\.^\//]/\\&/g' <<<"$APACHE_LOG_DIR_LIVE")
echo "$(date) apache document root folders: $APACHE_DOCUMENT_ROOT $APACHE_DOCUMENT_ROOT_LIVE $APACHE_DOCUMENT_ROOT_LIVE_ESC"
echo "$(date) apache site root folders: $APACHE_SITE_ROOT $APACHE_SITE_ROOT_LIVE $APACHE_SITE_ROOT_LIVE_ESC"
echo "$(date) apache log folders: $APACHE_LOG_DIR $APACHE_LOG_DIR_LIVE $APACHE_LOG_DIR_LIVE_ESC"

find /etc/apache2 -type f -exec sed -i -e "s/\${APACHE_SITE_ROOT}/$APACHE_SITE_ROOT_LIVE_ESC/g" {} +
find /etc/apache2 -type f -exec sed -i -e "s/\${APACHE_DOCUMENT_ROOT}/$APACHE_DOCUMENT_ROOT_LIVE_ESC/g" {} +
find /etc/apache2 -type f -exec sed -i -e "s/\${APACHE_LOG_DIR}/$APACHE_LOG_DIR_LIVE_ESC/g" {} +
find /usr/local/etc/php/conf.d -type f -exec sed -i -e "s/\${APACHE_LOG_DIR}/$APACHE_LOG_DIR_LIVE_ESC/g" {} +

# One-time seeding: if homelive is missing core, seed from home; else keep homelive -> home
if [[ ! -f "/homelive/site/wwwroot/index.php" ]]; then
	echo "$(date) Seeding /homelive from /home via Unison (-force /home)"
	unison default -force /home
else
	echo "$(date) Starting initial sync from /homelive to /home"
	unison default -force /homelive
fi

if supervisorctl -s unix:///var/run/supervisor.sock -u supervisor -p localonly restart apache2; then
  log_info "Apache restarted via supervisor"
else
  log_warn "Apache restart via supervisor failed (continuing)"
fi

# Ensure bundled WordPress Azure Monitor plugin is available on persistent storage
if [[ -d "/opt/wordpress-azure-monitor" ]]; then
    mkdir -p /home/site/wwwroot/wp-content/plugins /homelive/site/wwwroot/wp-content/plugins
    log_info "Copying bundled wordpress-azure-monitor plugin to persistent and live paths"
    if rsync -a /opt/wordpress-azure-monitor/ /home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor/; then
      log_info "Plugin copied to /home path"
    else
      log_warn "Plugin copy to /home failed (continuing)"
    fi
    if rsync -a /opt/wordpress-azure-monitor/ /homelive/site/wwwroot/wp-content/plugins/wordpress-azure-monitor/; then
      log_info "Plugin copied to /homelive path"
    else
      log_warn "Plugin copy to /homelive failed (continuing)"
    fi
fi

if [[ "${USE_SYSTEM_CRON:-1}" == "1" || "${USE_SYSTEM_CRON:-1}" == "true" ]]; then
  log_info "Installing WP cron (every 10m) for /homelive path"
  (crontab -l 2>/dev/null; echo "*/10 * * * * . /etc/profile; (/bin/date && cd /homelive/site/wwwroot && /usr/local/bin/wp --allow-root cron event run --due-now) | grep -v \"Warning:\" >> /home/LogFiles/sync/cron.log  2>&1") | crontab
fi

(crontab -l 2>/dev/null; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/apache2 > /dev/null") | crontab
log_info "Installed daily logrotate cron for /etc/logrotate.d/apache2"

if supervisorctl -s unix:///var/run/supervisor.sock -u supervisor -p localonly start sync; then
  log_info "Started unison sync process"
else
  log_warn "Failed to start unison sync process (continuing)"
fi

# Defer plugin auto-activation until core is installed (optional dev convenience)
if [[ -n "${WAZM_AUTO_ACTIVATE}" && "${WAZM_AUTO_ACTIVATE}" == "1" ]]; then
	# Try homelive first
	log_info "Attempting auto-activate wordpress-azure-monitor on /homelive if core is installed"
	WP_CLI_ALLOW_ROOT=1 sh -lc "cd '/homelive/site/wwwroot' && wp core is-installed --quiet && wp plugin activate wordpress-azure-monitor --quiet" && log_info "Plugin auto-activated on /homelive" || log_warn "Plugin auto-activation on /homelive skipped/failed"
	# Then try home (dev path)
	log_info "Attempting auto-activate wordpress-azure-monitor on /home if core is installed"
	WP_CLI_ALLOW_ROOT=1 sh -lc "cd '/home/site/wwwroot' && wp core is-installed --quiet && wp plugin activate wordpress-azure-monitor --quiet" && log_info "Plugin auto-activated on /home" || log_warn "Plugin auto-activation on /home skipped/failed"
fi

cat >/home/syncstatus <<EOL
Sync completed: $(date)

Sync took $SECONDS seconds
EOL
echo "$(date) Sync enabled - init complete"
fi
