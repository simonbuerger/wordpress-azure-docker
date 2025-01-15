FROM php:8.0-apache

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
    gnupg2 \
    ocaml \
    inotify-tools \
    rsync \
	; \
	rm -rf /var/lib/apt/lists/*

# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libfreetype6-dev \
		libjpeg-dev \
		libmagickwand-dev \
		libpng-dev \
		libzip-dev \
		libxml2-dev \
    build-essential \
	; \
		# --------
		# ~. tools
		# --------
		# wp-cli
	curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
		&& chmod +x wp-cli.phar \
		&& mv wp-cli.phar /usr/local/bin/wp \
		&& wget https://aka.ms/downloadazcopy-v10-linux \
		&& tar -xvf downloadazcopy-v10-linux \
		&& cp ./azcopy_linux_amd64_*/azcopy /usr/bin/ \
		&& rm -rf ./azcopy_linux_amd64_* \
		&& rm -rf ./downloadazcopy-v10-linux \
	; \
		# unison
  cd /tmp && \
    wget https://github.com/bcpierce00/unison/archive/v2.52.1.tar.gz && \
    tar xvf v2.52.1.tar.gz && \
    cd unison-2.52.1 && \
    sed -i -e 's/GLIBC_SUPPORT_INOTIFY 0/GLIBC_SUPPORT_INOTIFY 1/' src/fsmonitor/linux/inotify_stubs.c && \
    make UISTYLE=text NATIVE=true STATIC=true && \
    cp src/unison src/unison-fsmonitor /usr/local/bin && \
    rm -rf /tmp/unison-2.52.1 \
  ; \
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg \
	; \
	docker-php-ext-install -j "$(nproc)" \
		bcmath \
		exif \
		gd \
		mysqli \
		zip \
		opcache \
		soap \
    pdo \
    pdo_mysql \
	; \
	pecl install imagick; \
	pecl install redis; \
  pecl install apcu; \
	docker-php-ext-enable imagick; \
	docker-php-ext-enable redis; \
	docker-php-ext-enable apcu; \
	rm -r /tmp/pear; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
	docker-php-ext-enable opcache; \
	{ \
		echo 'opcache.memory_consumption=192'; \
		echo 'opcache.interned_strings_buffer=16'; \
		echo 'opcache.max_accelerated_files=8000'; \
		echo 'opcache.revalidate_freq=30'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
ENV APACHE_LOG_DIR=/home/LogFiles/sync/apache2
ENV APACHE_DOCUMENT_ROOT=/home/site/wwwroot
ENV APACHE_SITE_ROOT=/home/site/

ENV WP_CONTENT_ROOT=/home/site/wwwroot/wp-content

RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'upload_max_filesize=128M'; \
		echo 'memory_limit=512M'; \
		echo 'post_max_size=1024M'; \
		echo 'max_execution_time=900'; \
		echo 'max_input_time=900'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = ${APACHE_LOG_DIR}/php-error.log'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

RUN set -eux; \
	a2enmod rewrite expires headers; \
	echo 'CustomLog /dev/null combined' > /etc/apache2/conf-enabled/other-vhosts-access-log.conf; \
  	{ \
		echo 'ServerSignature Off'; \
# these IP ranges are reserved for "private" use and should thus *usually* be safe inside Docker
		echo 'ServerTokens Prod'; \
		echo 'DocumentRoot ${APACHE_DOCUMENT_ROOT}'; \
		echo 'DirectoryIndex default.htm default.html index.htm index.html index.php hostingstart.html'; \
		echo 'CustomLog /dev/null combined'; \
		echo '<FilesMatch "\.(?i:ph([[p]?[0-9]*|tm[l]?))$">'; \
		echo '   SetHandler application/x-httpd-php'; \
		echo '</FilesMatch>'; \
		echo 'EnableMMAP Off'; \
	} >> /etc/apache2/apache2.conf; \
  rm -rf /etc/apache2/sites-enabled/000-default.conf; \
	\
# https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html
	a2enmod remoteip; \
	{ \
		echo 'RemoteIPHeader X-Forwarded-For'; \
# these IP ranges are reserved for "private" use and should thus *usually* be safe inside Docker
		echo 'RemoteIPTrustedProxy 10.0.0.0/8'; \
		echo 'RemoteIPTrustedProxy 172.16.0.0/12'; \
		echo 'RemoteIPTrustedProxy 192.168.0.0/16'; \
		echo 'RemoteIPTrustedProxy 169.254.0.0/16'; \
		echo 'RemoteIPTrustedProxy 127.0.0.0/8'; \
	} > /etc/apache2/conf-available/remoteip.conf; \
	a2enconf remoteip; \
# https://github.com/docker-library/wordpress/issues/383#issuecomment-507886512
# (replace all instances of "%h" with "%a" in LogFormat)
	find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +

RUN set -eux; \
	version='5.7'; \
	sha1='76d1332cfcbc5f8b17151b357999d1f758faf897'; \
	\
	curl -o wordpress.tar.gz -fL "https://wordpress.org/wordpress-$version.tar.gz"; \
	echo "$sha1 *wordpress.tar.gz" | sha1sum -c -; \
	\
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
	tar -xzf wordpress.tar.gz -C /usr/src/; \
	rm wordpress.tar.gz; \
	\
# https://wordpress.org/support/article/htaccess/
	[ ! -e /usr/src/wordpress/.htaccess ]; \
	{ \
		echo '# BEGIN WordPress'; \
		echo ''; \
		echo 'RewriteEngine On'; \
		echo 'RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]'; \
		echo 'RewriteBase /'; \
		echo 'RewriteRule ^index\.php$ - [L]'; \
		echo 'RewriteCond %{REQUEST_FILENAME} !-f'; \
		echo 'RewriteCond %{REQUEST_FILENAME} !-d'; \
		echo 'RewriteRule . /index.php [L]'; \
		echo ''; \
		echo '# END WordPress'; \
	} > /usr/src/wordpress/.htaccess; \
	\
	chown -R www-data:www-data /usr/src/wordpress; \
# pre-create wp-content (and single-level children) for folks who want to bind-mount themes, etc so permissions are pre-created properly instead of root:root
# wp-content/cache: https://github.com/docker-library/wordpress/issues/534#issuecomment-705733507
	mkdir wp-content; \
	for dir in /usr/src/wordpress/wp-content/*/ cache; do \
		dir="$(basename "${dir%/}")"; \
		mkdir "wp-content/$dir"; \
	done; \
	chown -R www-data:www-data wp-content; \
	chmod -R 777 wp-content

RUN \
  echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' | tee /etc/apt/sources.list.d/newrelic.list; \
  wget -O- https://download.newrelic.com/548C16BF.gpg | apt-key add -; \
  apt-get update; \
  apt-get -y install newrelic-php5; \
  NR_INSTALL_SILENT=1 newrelic-install install; \
  sed -i -e "s/REPLACE_WITH_REAL_KEY/\${NEWRELIC_KEY}/" \
  -e "s/newrelic.appname[[:space:]]=[[:space:]].*/newrelic.appname=\"\${WEBSITE_HOSTNAME}\"/" \
  -e '$anewrelic.distributed_tracing_enabled=true' \
  -e '$anewrelic.framework.wordpress.hooks=true' \
  -e '$anewrelic.daemon.start_timeout=5s' \
  -e '$anewrelic.daemon.app_connect_timeout=10s' \
  $(php -r "echo(PHP_CONFIG_FILE_SCAN_DIR);")/newrelic.ini

RUN echo "root:Docker!" | chpasswd
RUN echo fs.inotify.max_user_watches=500000 | tee -a /etc/sysctl.conf
RUN mkdir -p /root/.unison
RUN [ ! -e /root/.unison/default.prf ]; \
	{ \
    echo 'root = /home'; \
    echo 'root = /homelive'; \
    echo ''; \
    echo '# Sync options'; \
    echo 'auto=true'; \
    echo 'backups=false'; \
    echo 'batch=true'; \
    echo 'contactquietly=true'; \
    echo 'fastcheck=true'; \
    echo 'maxthreads=10'; \
    echo 'prefer=newer'; \
    echo 'silent=true'; \
    echo 'perms=0'; \
    echo 'dontchmod=true'; \
    echo 'owner=false'; \
    echo ''; \
    echo 'path=site/wwwroot'; \
    echo 'path=LogFiles/sync'; \
    echo ''; \
    echo '# Files to ignore'; \
    echo 'ignore = Path site/wwwroot/wp-content/uploads'; \
    echo 'ignore = Path .git/*'; \
    echo 'ignore = Path .idea/*'; \
    echo 'ignore = Name *docker.log'; \
    echo 'ignore = Name *___jb_tmp___*'; \
    echo 'ignore = Name {.*,*}.sw[pon]'; \
    echo ''; \
    echo '# Additional user configuration'; \
	} > /root/.unison/default.prf;
RUN mkdir -p /home/LogFiles/sync
RUN mkdir -p /home/LogFiles/sync/apache2
RUN mkdir -p /home/LogFiles/sync/archive
RUN mkdir -p /homelive/LogFiles/sync
RUN mkdir -p /homelive/LogFiles/sync/apache2
RUN mkdir -p /homelive/LogFiles/sync/archive
RUN touch /homelive/LogFiles/sync/cron.log
RUN touch /home/LogFiles/supervisor.log
RUN touch /home/LogFiles/sync-init.log
RUN touch /home/LogFiles/sync-init-error.log
RUN touch /home/LogFiles/sync/supervisor.log
RUN chmod -R 0777 /homelive
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_SITE_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

RUN mkdir -p /tmp
COPY sshd_config /etc/ssh/
COPY ssh_setup.sh /tmp
RUN chmod -R +x /tmp/ssh_setup.sh \
	 && (sleep 1;/tmp/ssh_setup.sh 2>&1 > /dev/null) \
	 && rm -rf /tmp/*
COPY logrotate.d /etc/logrotate.d
COPY DigiCertGlobalRootG2.crt.pem /usr/
COPY DigiCertGlobalRootCA.crt.pem /usr/

ENV WEBSITE_ROLE_INSTANCE_ID localRoleInstance
ENV WEBSITE_INSTANCE_ID localInstance
COPY --chown=www-data:www-data wp-config-docker.php /usr/src/wordpress/
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
COPY scripts/fix-wordpress-permissions.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/fix-wordpress-permissions.sh
COPY scripts/sync-init.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/sync-init.sh

# RUN (crontab -l -u root; echo "*/10 * * * * . /etc/profile; fix-wordpress-permissions.sh /homelive/site/wwwroot > /dev/null") | crontab

ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

WORKDIR /homelive/site/wwwroot

EXPOSE 2222 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord"]
