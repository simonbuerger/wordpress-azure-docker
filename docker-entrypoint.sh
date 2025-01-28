#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /home/LogFiles/sync/apache2
mkdir -p /home/LogFiles/sync/archive

cd /homelive/site/wwwroot

eval $(printenv | sed -n "s/^\([^=]\+\)=\(.*\)$/export \1=\2/p" | sed 's/"/\\\"/g' | sed '/=/s//="/' | sed 's/$/"/' >> /etc/profile)

exec "$@"
