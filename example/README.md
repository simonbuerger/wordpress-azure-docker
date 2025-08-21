# WordPress Dev Environment (Docker Compose)

This example spins up the dev variant of the WordPress image and a MySQL database for local development.

## Prerequisites
- Docker and Docker Compose

## Quick start (simple)
```bash
cd example
docker compose up -d
# Open http://localhost:8080
```

- WordPress files map to `example/src` → container `/home/site/wwwroot` for live edits.
- MySQL data persists in the `db_data` volume.
- This simple compose uses the dev image with sync enabled and no plugin mounts.

## Contributor/dev compose
Use `docker-compose.dev.yml` for developing the image and the bundled plugin (mounts + Xdebug). This file builds a local dev image automatically if missing:
```bash
cd example
docker compose -f docker-compose.dev.yml up -d --build
# Open http://localhost:8080
```

## Use a locally built dev image
Build a local dev image for PHP 8.4 and point Compose at it:
```bash
# From repo root
docker build --target dev --build-arg PHP_VERSION=8.4 -t local/wordpress-azure:8.4-dev .

# In example/docker-compose.yml or example/docker-compose.dev.yml, set image to local tag
# services.wordpress.image: local/wordpress-azure:8.4-dev

cd example
docker compose up -d --build
```

## Plugin fast dev loop (dev compose)
With `docker-compose.dev.yml`, the `wordpress-azure-monitor` plugin is live-mounted into the container:
- Host path: `../wordpress-plugin/wordpress-azure-monitor`
- Container paths:
  - `/home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor`
  - `/homelive/site/wwwroot/wp-content/plugins/wordpress-azure-monitor`

Activate the plugin (run once):
```bash
cd example
docker compose -f docker-compose.dev.yml exec --user www-data -w /home/site/wwwroot wordpress wp plugin activate wordpress-azure-monitor
```

Edit plugin files on your host; refresh wp-admin to see changes immediately.

## Xdebug (dev compose)
- Default config enables `develop,debug` and starts with each request in the dev compose.
- For IDEs listening on port 9003, ensure host is `host.docker.internal` (set via `XDEBUG_CONFIG`).

## Environment
- WordPress docroot: `/home/site/wwwroot`
- Logs: `/home/LogFiles/sync`
- DB connection from WordPress:
  - Host: `db`
  - Port: `3306`
  - DB: `wordpress`
  - User: `wordpress`
  - Pass: `wordpress`

## WP-CLI usage
Run WP-CLI inside the `wordpress` service with the right user and path:
```bash
# Example: show core version
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp core version

# List plugins
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp plugin list

# Activate plugin
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp plugin activate wordpress-azure-monitor

# Run a WP-CLI command non-interactively (CI-friendly)
docker compose exec -T --user www-data -w /home/site/wwwroot wordpress wp option get siteurl
```

Optional shell alias for convenience (add to your `~/.zshrc` or `~/.bashrc`):
```bash
alias dcwp='docker compose exec --user www-data -w /home/site/wwwroot wordpress wp'
# usage:
dcwp plugin list
```

Open a shell in the container (root or www-data):
```bash
# Root shell
docker compose exec wordpress bash

# www-data shell
docker compose exec --user www-data -w /home/site/wwwroot wordpress bash
```

## Tear down
```bash
cd example
docker compose down -v
```
