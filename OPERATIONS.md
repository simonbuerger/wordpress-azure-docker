### Operations Guide

Operational reference for running `bluegrassdigital/wordpress-azure-sync` on Azure App Service or similar.

#### Image variants
- Moving tags (mutable): `:8.3-latest`, `:8.4-latest`, `:8.3-dev-latest`, `:8.4-dev-latest`, `:8.x-stable`, and `:<full-php-version>` if reused across releases.
- Immutable (per-build) tags: `:8.3-build-<git-sha>` and `:8.3-dev-build-<git-sha>`.
- Note: `:<full-php-version>` reflects the PHP engine version inside the image (e.g., `8.3.11`) but may be retagged by newer builds that keep the same PHP version. Treat it as mutable unless you verify the digest.

#### Key environment variables
- `DOCKER_SYNC_ENABLED=1` to enable `/home` ↔ `/homelive` sync.
- `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true` to persist `/home` on App Service (required for WordPress content persistence and sync).
- `APACHE_DOCUMENT_ROOT=/home/site/wwwroot` (default)
- `APACHE_SITE_ROOT=/home/site/` (default)
- `APACHE_LOG_DIR=/home/LogFiles/sync/apache2` (default)
- `WP_CONTENT_ROOT=/home/site/wwwroot/wp-content` (default)
- `WORDPRESS_CONFIG_EXTRA` for local overrides (e.g., disable SSL for local DB).
- `USE_SYSTEM_CRON=1` to run WP cron via system cron (default); set to `0` to use WP's built-in cron.
- New Relic: `NEWRELIC_KEY`, `WEBSITE_HOSTNAME` (agent install is best-effort).

#### Logs and health
- Healthcheck: HTTP on `/` every 30s.
- Logs: `/home/LogFiles/sync`, Apache at `/home/LogFiles/sync/apache2`.
- Supervisord manages: apache2, cron, ssh, syncinit, sync (Unison).

#### First-time WordPress install (Azure App Service)
- Database: provision MySQL and add an App Setting named `MYSQLCONNSTR_defaultConnection` with the Azure-style connection string:
  - `Data Source=<host>;Database=<db>;User Id=<user>;Password=<pass>`
- Image tag: use an immutable per-build tag (see below). Enable a staging slot with Health check for zero-downtime.
- App settings (recommended):
  - `DOCKER_SYNC_ENABLED=1` (sync /home ↔ /homelive for performance)
  - Optional: `HOST_DOMAIN=<your-domain>` (ensures correct `WP_HOME`/`WP_SITEURL`), `WORDPRESS_CONFIG_EXTRA` for small overrides
- First boot behavior (automatic):
  - Downloads WordPress core to `/home/site/wwwroot` if missing
  - Creates `/home/site/wwwroot/wp-config.php` from the bundled template, reading `MYSQLCONNSTR_defaultConnection`
  - Sets up cron and log rotation; adjusts Apache to use `/homelive` if `DOCKER_SYNC_ENABLED` is set
- Complete setup: browse to your site domain and follow the WordPress installer.
- .htaccess: WordPress normally writes this. If needed, copy our template to `/home/site/wwwroot/.htaccess` (persisted storage) from `file-templates/htaccess-template`.

#### WordPress Azure Monitor plugin
- Included in the image at `/opt/wordpress-azure-monitor`.
- To use it, ensure the plugin directory exists under `/home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor` (persisted storage). Example one-time setup:
```
mkdir -p /home/site/wwwroot/wp-content/plugins
cp -r /opt/wordpress-azure-monitor /home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor
```
- Auto-activation: set `WAZM_AUTO_ACTIVATE=1` in App Settings. On startup, once WordPress core is installed, the container will attempt to activate the plugin via WP‑CLI.
- Manual activation (alternative):
```
wp plugin activate wordpress-azure-monitor
```

#### Azure App Service deployment guidance
- Use immutable per-build tags in production (e.g., `bluegrassdigital/wordpress-azure-sync:8.3-build-<git-sha>`), or pin by digest. Avoid `:latest`, `:stable`, and `:<full-php-version>` if you require strict immutability.
- For zero-downtime, deploy to a staging slot with Health check enabled (e.g., `/` or `/healthz`) and swap once healthy. A single-instance app updated in-place may have a brief interruption.
- To apply updates, change the configured image tag or restart the app/slot so App Service pulls the new image. If you wire up webhooks/CD to your registry, a new push to the same tag can trigger an automatic pull + restart.
- Security/patches: we publish patched images (new immutable tags) when upstream components update. Track releases and move to the newer immutable tag via your staging → prod flow.

Deploying files to `/home` (zip deploy/FTP)
- When `DOCKER_SYNC_ENABLED=1`, Apache serves from `/homelive`, and a background sync pushes changes from `/homelive` → `/home`.
- Files deployed directly to `/home/site/wwwroot` (zip deploy/FTP) will not be visible while sync is enabled.
  - Restart the app/slot to pick up the changes. Avoid manual rsync while Unison is running.

Practical flow
- Configure staging slot with an immutable per-build tag (e.g., `:8.3-build-<git-sha>`), or pin by digest.
- Validate, then swap slots.

#### Available tags (what to pick)
- Use for production: `:8.3-build-<git-sha>` (immutable per commit) or a digest pin.
- Acceptable for non-production: `:<full-php-version>` (may move if multiple releases share the same PHP version).
- Avoid in production: `:8.3-latest`, `:8.4-latest`, `:8.x-stable` (moving tags).

#### Upgrades
- To add a PHP version, build with `--build-arg PHP_VERSION=...` and add targets in `docker-bake.hcl` and CI matrix.
- Imagick pinned to 3.8.0 for PHP 8.4+ compatibility.


