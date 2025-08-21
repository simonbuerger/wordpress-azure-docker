#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /home/LogFiles/sync/apache2
mkdir -p /home/LogFiles/sync/archive

# Allow env-driven PHP display_errors toggle (PHP_DISPLAY_ERRORS=On|Off)
if [[ -n "${PHP_DISPLAY_ERRORS:-}" ]]; then
  echo "display_errors=${PHP_DISPLAY_ERRORS}" > /usr/local/etc/php/conf.d/zz-runtime-display-errors.ini
fi

cd /homelive/site/wwwroot

# export env to /etc/profile for subshells
eval $(printenv | sed -n "s/^\([^=]\+\)=\(.*\)$/export \1=\2/p" | sed 's/"/\\\"/g' | sed '/=/s//="/' | sed 's/$/"/' >> /etc/profile)

exec "$@"
