# This Dockerfile sets up a WordPress environment on top of the php:8.3-apache base image.
#
# 1. Installs essential system packages including Ghostscript, SSH, cron, MariaDB client, rsync, inotify, and supervisord.
# 2. Adds WordPress CLI (wp-cli), AzCopy for file handling, and Unison for file synchronization (multi-stage to keep final image lean).
# 3. Installs required PHP extensions and applies production-oriented PHP and Apache settings.
# 4. Configures Apache modules (rewrite, headers, remoteip) and log behavior; adjusts for Azure environment paths.
# 5. Attempts New Relic agent setup (best-effort) and configures at runtime via environment variables.
# 6. Prepares directories and files for WordPress core, logs, and scripts; uses supervisord as the main process.
# 7. Exposes SSH and HTTP ports and runs an entrypoint to initialize runtime behavior.

ARG PHP_VERSION=8.3

# --- Build stage for Unison (kept out of the final image) ---
FROM debian:bookworm-slim AS unison-builder
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		unison \
		ca-certificates; \
	rm -rf /var/lib/apt/lists/*; \
	install -Dm755 /usr/bin/unison /out/unison; \
	if [ -x /usr/bin/unison-fsmonitor ]; then install -Dm755 /usr/bin/unison-fsmonitor /out/unison-fsmonitor; else echo 'echo "unison-fsmonitor not available; unison will still function"' > /out/unison-fsmonitor && chmod +x /out/unison-fsmonitor; fi

# --- Final runtime image ---
FROM php:${PHP_VERSION}-apache AS runtime

ARG OCI_TITLE="wordpress-azure"
ARG OCI_DESCRIPTION="WordPress on php-apache with Azure-specific tooling (AzCopy), Unison sync, New Relic, SSH, and supervisord"
ARG OCI_SOURCE="https://hub.docker.com/r/bluegrassdigital/wordpress-azure-sync"
ARG OCI_VENDOR="Bluegrass Digital"
ARG OCI_LICENSES="MIT"

LABEL org.opencontainers.image.title="$OCI_TITLE" \
	org.opencontainers.image.description="$OCI_DESCRIPTION" \
	org.opencontainers.image.source="$OCI_SOURCE" \
	org.opencontainers.image.vendor="$OCI_VENDOR" \
	org.opencontainers.image.licenses="$OCI_LICENSES"

COPY --from=ghcr.io/mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# persistent dependencies
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		# Ghostscript is required for rendering PDF previews
		ghostscript \
		openssh-server \
		wget \
		cron \
		curl \
		logrotate \
		mariadb-client \
		supervisor \
		gnupg \
		inotify-tools \
		rsync \
		ca-certificates; \
	rm -rf /var/lib/apt/lists/*

# tools: wp-cli and AzCopy
RUN set -eux; \
	# wp-cli
	curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp; \
	chmod +x /usr/local/bin/wp; \
	# AzCopy (arch-aware)
	arch=$(dpkg --print-architecture); \
	case "$arch" in \
	  amd64) AZCOPY_URL="https://aka.ms/downloadazcopy-v10-linux"; PATTERN="azcopy_linux_amd64_*" ;; \
	  arm64) AZCOPY_URL="https://aka.ms/downloadazcopy-v10-linux-arm64"; PATTERN="azcopy_linux_arm64_*" ;; \
	  *) AZCOPY_URL="https://aka.ms/downloadazcopy-v10-linux"; PATTERN="azcopy_linux_amd64_*" ;; \
	esac; \
	curl -fsSL "$AZCOPY_URL" -o azcopy.tgz; \
	tar -xvf azcopy.tgz; \
	cp ./${PATTERN}/azcopy /usr/bin/; \
	rm -rf ./${PATTERN} ./azcopy.tgz

# Unison binaries from the builder stage
COPY --from=unison-builder /out/unison /usr/local/bin/unison
COPY --from=unison-builder /out/unison-fsmonitor /usr/local/bin/unison-fsmonitor

# PHP extensions
ARG IMAGICK_PACKAGE=imagick-3.8.0
RUN set -eux; \
	install-php-extensions \
		apcu \
    bcmath \
		exif \
		gd \
		mysqli \
		zip \
		opcache \
		soap \
    pdo \
    pdo_mysql \
    ${IMAGICK_PACKAGE} ;

# Apache and PHP config via templates
ENV APACHE_LOG_DIR=/home/LogFiles/sync/apache2
ENV APACHE_DOCUMENT_ROOT=/home/site/wwwroot
ENV APACHE_SITE_ROOT=/home/site/
ENV WP_CONTENT_ROOT=/home/site/wwwroot/wp-content

# Copy PHP conf templates
COPY file-templates/php/conf.d/opcache-recommended.ini /usr/local/etc/php/conf.d/opcache-recommended.ini
COPY file-templates/php/conf.d/error-logging.ini /usr/local/etc/php/conf.d/error-logging.ini

# Copy Apache conf templates
COPY file-templates/apache/other-vhosts-access-log.conf /etc/apache2/conf-enabled/other-vhosts-access-log.conf
COPY file-templates/apache/apache2-extra.conf /etc/apache2/conf-available/apache2-extra.conf
COPY file-templates/apache/remoteip.conf /etc/apache2/conf-available/remoteip.conf

# Provide wp-config template for init script
COPY file-templates/wp-config-docker.php /usr/src/wordpress/wp-config-docker.php

# Enable Apache modules and configs
RUN set -eux; \
	a2enmod rewrite expires headers remoteip; \
	a2enconf apache2-extra remoteip; \
	# Replace %h with %a in LogFormat
	find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +; \
	# Remove default site config
	rm -rf /etc/apache2/sites-enabled/000-default.conf

# New Relic setup (best-effort)
RUN set -eux; \
	if command -v gpg >/dev/null 2>&1; then \
	  install -d -m 0755 /etc/apt/keyrings; \
	  (curl -fsSL https://download.newrelic.com/548C16BF.gpg | gpg --dearmor -o /etc/apt/keyrings/newrelic.gpg) || true; \
	  echo 'deb [signed-by=/etc/apt/keyrings/newrelic.gpg] http://apt.newrelic.com/debian/ newrelic non-free' > /etc/apt/sources.list.d/newrelic.list; \
	else \
	  echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' > /etc/apt/sources.list.d/newrelic.list; \
	fi; \
	apt-get update || true; \
	if apt-get -y install newrelic-php5; then \
	  NR_INSTALL_SILENT=1 newrelic-install install || true; \
	  if [ -f "$(php -r "echo(PHP_CONFIG_FILE_SCAN_DIR);")/newrelic.ini" ]; then \
	    sed -i -e "s/REPLACE_WITH_REAL_KEY/\${NEWRELIC_KEY}/" \
	    -e "s/newrelic.appname[[:space:]]=[[:space:]].*/newrelic.appname=\"\${WEBSITE_HOSTNAME}\"/" \
	    -e '$anewrelic.distributed_tracing_enabled=true' \
	    -e '$anewrelic.framework.wordpress.hooks=true' \
	    -e '$anewrelic.daemon.start_timeout=5s' \
	    -e '$anewrelic.daemon.app_connect_timeout=10s' \
	    "$(php -r "echo(PHP_CONFIG_FILE_SCAN_DIR);")/newrelic.ini" || true; \
	  fi; \
	else \
	  echo 'New Relic agent install skipped (repo/package unavailable)'; \
	fi

# System and Unison config via templates
COPY file-templates/sysctl.d/99-wordpress.conf /etc/sysctl.d/99-wordpress.conf
COPY file-templates/unison/default.prf /root/.unison/default.prf
RUN set -eux; \
	echo "root:Docker!" | chpasswd; \
	mkdir -p /home/LogFiles/sync /home/LogFiles/sync/apache2 /home/LogFiles/sync/archive; \
	mkdir -p /homelive/LogFiles/sync /homelive/LogFiles/sync/apache2 /homelive/LogFiles/sync/archive; \
	touch /homelive/LogFiles/sync/cron.log /home/LogFiles/supervisor.log /home/LogFiles/sync-init.log /home/LogFiles/sync-init-error.log /home/LogFiles/sync/supervisor.log; \
	chmod -R 0777 /homelive; \
	sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf; \
	sed -ri -e 's!/var/www/!${APACHE_SITE_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

RUN mkdir -p /tmp
COPY sshd_config /etc/ssh/
COPY ssh_setup.sh /tmp
RUN chmod -R +x /tmp/ssh_setup.sh \
	 && (sleep 1;/tmp/ssh_setup.sh 2>&1 > /dev/null) \
	 && rm -rf /tmp/*
COPY logrotate.d /etc/logrotate.d
COPY DigiCertGlobalRootG2.crt.pem /usr/
COPY DigiCertGlobalRootCA.crt.pem /usr/

# Bundle the monitor plugin (optional auto-activation at runtime)
COPY wordpress-plugin/wordpress-azure-monitor /opt/wordpress-azure-monitor

ENV WEBSITE_ROLE_INSTANCE_ID=localRoleInstance
ENV WEBSITE_INSTANCE_ID=localInstance
COPY docker-entrypoint.sh /usr/local/bin/
COPY scripts/fix-wordpress-permissions.sh /usr/local/bin/
COPY scripts/sync-init.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/fix-wordpress-permissions.sh /usr/local/bin/sync-init.sh

# RUN (crontab -l -u root; echo "*/10 * * * * . /etc/profile; fix-wordpress-permissions.sh /homelive/site/wwwroot > /dev/null") | crontab

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

WORKDIR /homelive/site/wwwroot

EXPOSE 2222 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -fsS http://localhost/ || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord"]

# --- Dev variant (extra tools, composer, xdebug, and dev PHP overrides) ---
FROM runtime AS dev
RUN set -eux; \
	rm -f /etc/apt/sources.list.d/newrelic.list || true; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		git \
		vim \
		nano \
		less \
		zip \
		unzip \
		make \
		procps \
		iputils-ping \
		netcat-openbsd; \
	rm -rf /var/lib/apt/lists/*
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN set -eux; \
	install-php-extensions xdebug; \
	# dev defaults: keep errors off by default; enable fast opcache reloads
	printf "display_errors=Off\n" > /usr/local/etc/php/conf.d/zz-dev-overrides.ini; \
	printf "display_startup_errors=Off\n" >> /usr/local/etc/php/conf.d/zz-dev-overrides.ini; \
	printf "error_reporting=E_ALL\n" >> /usr/local/etc/php/conf.d/zz-dev-overrides.ini; \
	printf "opcache.validate_timestamps=1\n" >> /usr/local/etc/php/conf.d/zz-dev-overrides.ini; \
	printf "opcache.revalidate_freq=0\n" >> /usr/local/etc/php/conf.d/zz-dev-overrides.ini
