### Operations Guide

Operational reference for running `bluegrassdigital/wordpress-azure-sync` on Azure App Service or similar.

#### Image variants
- `:8.3-latest`, `:8.4-latest` (prod)
- `:8.3-dev-latest`, `:8.4-dev-latest` (dev tools)
- `:8.x-stable` and `:<full-php-version>[-dev]` published on release tags.

#### Key environment variables
- `DOCKER_SYNC_ENABLED=1` to enable `/home` ↔ `/homelive` sync.
- `APACHE_DOCUMENT_ROOT=/home/site/wwwroot` (default)
- `APACHE_SITE_ROOT=/home/site/` (default)
- `APACHE_LOG_DIR=/home/LogFiles/sync/apache2` (default)
- `WP_CONTENT_ROOT=/home/site/wwwroot/wp-content` (default)
- `WORDPRESS_CONFIG_EXTRA` for local overrides (e.g., disable SSL for local DB).
- New Relic: `NEWRELIC_KEY`, `WEBSITE_HOSTNAME` (agent install is best-effort).

#### Logs and health
- Healthcheck: HTTP on `/` every 30s.
- Logs: `/home/LogFiles/sync`, Apache at `/home/LogFiles/sync/apache2`.
- Supervisord manages: apache2, cron, ssh, syncinit, sync (Unison).

#### CI/CD
- GitHub Actions builds multi-arch images and pushes tags.
- On branch push: `latest` tags only.
- On git tag `v*`: push `stable` and full PHP-version tags via imagetools.
- Required secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.

#### Upgrades
- To add a PHP version, build with `--build-arg PHP_VERSION=...` and add targets in `docker-bake.hcl` and CI matrix.
- Imagick pinned to 3.8.0 for PHP 8.4+ compatibility.


