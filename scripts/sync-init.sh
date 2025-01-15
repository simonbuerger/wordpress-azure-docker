#!/usr/bin/env bash

WP_CONTENT_ROOT_LIVE=$(echo $WP_CONTENT_ROOT | sed -e "s/\/home\//\/homelive\//g")
mkdir -p "$WP_CONTENT_ROOT/uploads"
mkdir -p "$WP_CONTENT_ROOT_LIVE"

ln -s "$WP_CONTENT_ROOT/uploads" "$WP_CONTENT_ROOT_LIVE"

if [[ -z "${DOCKER_SYNC_ENABLED}" ]]; then
cat >/home/syncstatus <<EOL
Sync disabled
EOL
echo "$(date) Sync disabled - init start"
echo "cd /home" >> /root/.bashrc

(crontab -l; echo "*/10 * * * * . /etc/profile; (/bin/date && cd /home/site/wwwroot && /usr/local/bin/wp --allow-root cron event run --due-now) | grep -v \"Warning:\" >> /home/LogFiles/cron.log  2>&1") | crontab

(crontab -l; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/apache2 > /dev/null") | crontab

echo "$(date) Sync disabled - init complete"
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

rsync -apoghW --no-compress /home/site/wwwroot/ /homelive/site/wwwroot/ --exclude 'wp-content' --exclude '*.unison.tmp' --chown "$WP_OWNER:$WP_GROUP" --chmod "D0755,F0644"
rsync -apoghW --no-compress "$WP_CONTENT_ROOT/" "$WP_CONTENT_ROOT_LIVE/" --exclude 'uploads' --exclude '*.unison.tmp' --chown "$WP_OWNER:$WP_GROUP" --chmod "D0775,F0664"
rsync -apoghW --no-compress /home/LogFiles/ /homelive/LogFiles/ --exclude '*.unison.tmp'
echo "$(date) Fixing directory permissions"

APACHE_DOCUMENT_ROOT_LIVE=$(echo $APACHE_DOCUMENT_ROOT | sed -e "s/\/home\//\/homelive\//g")

fix-wordpress-permissions.sh $APACHE_DOCUMENT_ROOT_LIVE

echo "$(date) Updating Apache to point to homlive rather than home"

ln -s "$WP_CONTENT_ROOT/uploads" "$WP_CONTENT_ROOT_LIVE"

APACHE_SITE_ROOT_LIVE=$(echo $APACHE_SITE_ROOT | sed -e "s/\/home\//\/homelive\//g")
APACHE_LOG_DIR_LIVE=$(echo $APACHE_LOG_DIR | sed -e "s/\/home\//\/homelive\//g")
APACHE_SITE_ROOT_LIVE_ESC=$(sed 's/[\*\.\/]/\\&/g' <<<"$APACHE_SITE_ROOT_LIVE")
APACHE_DOCUMENT_ROOT_LIVE_ESC=$(sed 's/[\*\.\/]/\\&/g' <<<"$APACHE_DOCUMENT_ROOT_LIVE")
APACHE_LOG_DIR_LIVE_ESC=$(sed 's/[\*\.\/]/\\&/g' <<<"$APACHE_LOG_DIR_LIVE")
echo "$(date) apache document root folders: $APACHE_DOCUMENT_ROOT $APACHE_DOCUMENT_ROOT_LIVE $APACHE_DOCUMENT_ROOT_LIVE_ESC"
echo "$(date) apache site root folders: $APACHE_SITE_ROOT $APACHE_SITE_ROOT_LIVE $APACHE_SITE_ROOT_LIVE_ESC"
echo "$(date) apache log folders: $APACHE_LOG_DIR $APACHE_LOG_DIR_LIVE $APACHE_LOG_DIR_LIVE_ESC"

find /etc/apache2 -type f -exec sed -i -e "s/\${APACHE_SITE_ROOT}/$APACHE_SITE_ROOT_LIVE_ESC/g" {} +
find /etc/apache2 -type f -exec sed -i -e "s/\${APACHE_DOCUMENT_ROOT}/$APACHE_DOCUMENT_ROOT_LIVE_ESC/g" {} +
find /etc/apache2 -type f -exec sed -i -e "s/\${APACHE_LOG_DIR}/$APACHE_LOG_DIR_LIVE_ESC/g" {} +
find /usr/local/etc/php/conf.d -type f -exec sed -i -e "s/\${APACHE_LOG_DIR}/$APACHE_LOG_DIR_LIVE_ESC/g" {} +

echo "$(date) Starting initial sync from /homelive to /home"

unison default -force /homelive

supervisorctl restart apache2

(crontab -l; echo "*/10 * * * * . /etc/profile; (/bin/date && cd /homelive/site/wwwroot && /usr/local/bin/wp --allow-root cron event run --due-now) | grep -v \"Warning:\" >> /homelive/LogFiles/sync/cron.log  2>&1") | crontab

(crontab -l; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/apache2-sync > /dev/null") | crontab

supervisorctl start sync

cat >/home/syncstatus <<EOL
Sync completed: $(date)

Sync took $SECONDS seconds
EOL
echo "$(date) Sync enabled - init complete"
fi
