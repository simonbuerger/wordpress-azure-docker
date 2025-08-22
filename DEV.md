### Developer Guide

Local development workflow for the dev image variant (composer, xdebug, tools).

#### Editor configuration
This repository includes an `.editorconfig` file so that compatible editors automatically
apply the project's formatting conventions. Ensure your editor supports EditorConfig.

#### Quick start (using Hub image)
```bash
cd example
docker compose up -d
# open http://localhost:8080
```

#### Manual WordPress install (first run)
```bash
docker compose exec --user www-data -w /homelive/site/wwwroot wordpress \
  wp core install \
  --url=http://localhost:8080 \
  --title='Local Dev' \
  --admin_user=admin \
  --admin_password=admin \
  --admin_email=admin@example.com \
  --skip-email
```

#### WP-CLI usage
```bash
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp plugin list
```

#### Xdebug
- Port 9003, host `host.docker.internal` (configurable via `XDEBUG_CONFIG`).

#### Paths you will edit
- Host `example/src` ↔ container `/home/site/wwwroot` (synced to `/homelive/site/wwwroot`)
- Plugin is mounted from `wordpress-plugin/wordpress-azure-monitor` to both locations for live edits.

#### Troubleshooting
- 403 after first boot: ensure WordPress files exist in `/homelive/site/wwwroot`; rerun sync by restarting container.
- DB connect errors: verify `WORDPRESS_CONFIG_EXTRA` overrides and the `db` service is healthy.
 - No admin bar badge: ensure plugin is active and check `/home/LogFiles/sync` logs.
