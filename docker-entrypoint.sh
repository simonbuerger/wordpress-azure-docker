#!/usr/bin/env bash
set -Eeuo pipefail

# find . -type d -name '*.unison.tmp' -exec rm -rf {} +

# unison default -perms -1 -force /home -dontchmod=false

# mkdir -p /homelive/site/wwwroot/wp-content
mkdir -p /home/LogFiles/sync/apache2
# mkdir -p /homelive/LogFiles/sync/apache2
mkdir -p /home/LogFiles/sync/archive
# mkdir -p /homelive/LogFiles/sync/archive

# ln -s /home/site/wwwroot/wp-content/uploads /homelive/site/wwwroot/wp-content

cd /homelive/site/wwwroot

# if [ ! -e index.php ] && [ ! -e wp-includes/version.php ]; then
#   wp --allow-root core download
#   echo >&2 "Complete! WordPress has been successfully installed to $PWD"
# fi

# echo "$PWD"
# if [ ! -s wp-config.php ]; then
#   for wpConfigDocker in \
#     wp-config-docker.php \
#     /usr/src/wordpress/wp-config-docker.php \
#   ; do
#     if [ -s "$wpConfigDocker" ]; then
#       echo >&2 "No 'wp-config.php' found in $PWD, but 'WORDPRESS_...' variables supplied; copying '$wpConfigDocker' (${wpEnvs[*]})"
#       # using "awk" to replace all instances of "put your unique phrase here" with a properly unique string (for AUTH_KEY and friends to have safe defaults if they aren't specified with environment variables)
#       awk '
#         /put your unique phrase here/ {
#           cmd = "head -c1m /dev/urandom | sha1sum | cut -d\\  -f1"
#           cmd | getline str
#           close(cmd)
#           gsub("put your unique phrase here", str)
#         }
#         { print }
#       ' "$wpConfigDocker" > wp-config.php
#       break
#     fi
#   done
# fi

# fix-wordpress-permissions.sh /homelive/site/wwwroot

eval $(printenv | sed -n "s/^\([^=]\+\)=\(.*\)$/export \1=\2/p" | sed 's/"/\\\"/g' | sed '/=/s//="/' | sed 's/$/"/' >> /etc/profile)

exec "$@"
