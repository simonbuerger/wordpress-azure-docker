#!/usr/bin/env bash

# This script initializes and manages WordPress content synchronization between /home and /homelive.
# It checks if DOCKER_SYNC_ENABLED is set, then either creates and configures sync tasks or disables them.
# Key operations:
# - Prepares folders and symbolic links for wp-content and logs.
# - Uses rsync to mirror files (excluding specific directories) and apply correct permissions.
# - Updates Apache configurations to point from /home to /homelive.
# - Sets up cron jobs for WordPress cron events and Apache log rotation.
# - Uses unison for one-way or two-way synchronization when DOCKER_SYNC_ENABLED is enabled.

WP_CONTENT_ROOT_LIVE=$(echo $WP_CONTENT_ROOT | sed -e "s/\/home\//\/homelive\//g")
mkdir -p "$WP_CONTENT_ROOT/uploads"
mkdir -p "$WP_CONTENT_ROOT_LIVE"

# Ensure uploads symlink exists in live path and points to persisted /home path
if [[ ! -L "$WP_CONTENT_ROOT_LIVE/uploads" ]]; then
    rm -rf "$WP_CONTENT_ROOT_LIVE/uploads" 2>/dev/null || true
    ln -s "$WP_CONTENT_ROOT/uploads" "$WP_CONTENT_ROOT_LIVE/uploads" || true
fi

if [[ -z "${DOCKER_SYNC_ENABLED}" ]]; then
cat >/home/syncstatus <<EOL
Sync disabled
EOL
echo "$(date) Sync disabled - init start"
echo "cd /home" >> /root/.bashrc

if [[ "${USE_SYSTEM_CRON:-1}" == "1" || "${USE_SYSTEM_CRON:-1}" == "true" ]]; then
  (crontab -l; echo "*/10 * * * * . /etc/profile; (/bin/date && cd /home/site/wwwroot && /usr/local/bin/wp --allow-root cron event run --due-now) | grep -v \"Warning:\" >> /home/LogFiles/cron.log  2>&1") | crontab
fi

(crontab -l; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/apache2 > /dev/null") | crontab

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
echo "$(date) Sync enabled - init start"

rm -rf /home/syncstatus

echo "cd /homelive" >> /root/.bashrc

echo "$(date) Starting unison sync from /home to /homelive"

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

rsync -apoghW --no-compress /home/site/wwwroot/ /homelive/site/wwwroot/ --exclude 'wp-content' --exclude '*.unison.tmp' --chown "$WP_OWNER:$WP_GROUP" --chmod "D0755,F0644"
rsync -apoghW --no-compress "$WP_CONTENT_ROOT/" "$WP_CONTENT_ROOT_LIVE/" --exclude 'uploads' --exclude '*.unison.tmp' --chown "$WP_OWNER:$WP_GROUP" --chmod "D0775,F0664"
rsync -apoghW --no-compress /home/LogFiles/ /homelive/LogFiles/ --exclude '*.unison.tmp'
echo "$(date) Fixing directory permissions"

APACHE_DOCUMENT_ROOT_LIVE=$(echo $APACHE_DOCUMENT_ROOT | sed -e "s/\/home\//\/homelive\//g")

fix-wordpress-permissions.sh $APACHE_DOCUMENT_ROOT_LIVE

echo "$(date) Updating Apache to point to homelive rather than home"

# Re-ensure uploads symlink without erroring if it already exists
if [[ ! -L "$WP_CONTENT_ROOT_LIVE/uploads" ]]; then
    rm -rf "$WP_CONTENT_ROOT_LIVE/uploads" 2>/dev/null || true
    ln -s "$WP_CONTENT_ROOT/uploads" "$WP_CONTENT_ROOT_LIVE/uploads" || true
fi

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

supervisorctl restart apache2

# Ensure bundled WordPress Azure Monitor plugin is available on persistent storage
if [[ -d "/opt/wordpress-azure-monitor" ]]; then
    mkdir -p /home/site/wwwroot/wp-content/plugins /homelive/site/wwwroot/wp-content/plugins
    rsync -a /opt/wordpress-azure-monitor/ /home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor/ || true
    rsync -a /opt/wordpress-azure-monitor/ /homelive/site/wwwroot/wp-content/plugins/wordpress-azure-monitor/ || true
fi

if [[ "${USE_SYSTEM_CRON:-1}" == "1" || "${USE_SYSTEM_CRON:-1}" == "true" ]]; then
  (crontab -l; echo "*/10 * * * * . /etc/profile; (/bin/date && cd /homelive/site/wwwroot && /usr/local/bin/wp --allow-root cron event run --due-now) | grep -v \"Warning:\" >> /homelive/LogFiles/sync/cron.log  2>&1") | crontab
fi

(crontab -l; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/apache2-sync > /dev/null") | crontab

supervisorctl start sync

# Defer plugin auto-activation until core is installed (optional dev convenience)
if [[ -n "${WAZM_AUTO_ACTIVATE}" && "${WAZM_AUTO_ACTIVATE}" == "1" ]]; then
	# Try homelive first
	WP_CLI_ALLOW_ROOT=1 sh -lc "cd '/homelive/site/wwwroot' && wp core is-installed --quiet && wp plugin activate wordpress-azure-monitor --quiet" || true
	# Then try home (dev path)
	WP_CLI_ALLOW_ROOT=1 sh -lc "cd '/home/site/wwwroot' && wp core is-installed --quiet && wp plugin activate wordpress-azure-monitor --quiet" || true
fi

cat >/home/syncstatus <<EOL
Sync completed: $(date)

Sync took $SECONDS seconds
EOL
echo "$(date) Sync enabled - init complete"
fi
