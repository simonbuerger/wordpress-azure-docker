# WordPress on Azure App Service (Docker image)
Optimized WordPress container for Azure App Service (Linux) with App Service Storage enabled. It mitigates high I/O latency by serving from a fast local path (`/homelive`) and syncing with the persistent path (`/home`).

## What this is
- A production-ready WordPress image (PHP 8.3/8.4 + Apache) tuned for Azure App Service.
- Ships with common PHP extensions, healthcheck, supervisord, and optional WordPress Azure Monitor plugin.
- Uses rsync + Unison to keep `/homelive` and `/home` in sync when `DOCKER_SYNC_ENABLED=1`.

## Quick start (Azure App Service)
- Image tag: use an immutable per-build tag for production (e.g., `bluegrassdigital/wordpress-azure-sync:8.3-build-<git-sha>`). Avoid `:latest` and `:stable` in production.
- App Settings:
  - `MYSQLCONNSTR_defaultConnection=Data Source=<host>;Database=<db>;User Id=<user>;Password=<pass>`
  - `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true`
  - `DOCKER_SYNC_ENABLED=1`
  - Optional: `USE_SYSTEM_CRON=1` (default) to run WP cron via system cron; set to `0` to use WP internal cron
  - Optional: `HOST_DOMAIN=<your-domain>`, `WORDPRESS_CONFIG_EXTRA=<php code>`, `WAZM_AUTO_ACTIVATE=1`
- First boot:
  - If `/home/site/wwwroot` is empty, the container downloads WordPress and creates `wp-config.php` from the built-in template.
  - Complete setup by visiting your site URL.
- .htaccess:
  - WordPress normally writes this; a hardened template is available at `file-templates/htaccess-template`.
- Zero-downtime:
  - Use deployment slots with Health check enabled and swap once warm.

### Deploying file changes
- With `DOCKER_SYNC_ENABLED=1`, the site is served from `/homelive`; changes deployed to `/home/site/wwwroot` (zip deploy/FTP) won’t show until a restart.
- For file deploys to `/home`, restart the app/slot to pick up changes. Avoid manual rsync while Unison is running.

## Documentation
- Full docs by role: see [`docs/`](docs/README.md)
- Operators: see [`OPERATIONS.md`](OPERATIONS.md) for deployment, tags, first-time install, plugin, and troubleshooting, and [`docs/wp-azure-tools.md`](docs/wp-azure-tools.md) for maintenance commands
- Developers: see [`DEV.md`](DEV.md) for local dev and example compose. Build the dev variant locally when contributing:
  - `docker build --target dev --build-arg PHP_VERSION=8.4 -t local/wordpress-azure:8.4-dev .`
  - Then point your compose file to `local/wordpress-azure:8.4-dev`.
- WordPress administrators: see [`docs/wordpress-azure-monitor.md`](docs/wordpress-azure-monitor.md) for the optional Azure Monitor plugin
- Release process: see [`RELEASING.md`](RELEASING.md) for tags, changelogs, weekly vs feature releases

## License
MIT
