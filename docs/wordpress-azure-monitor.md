# WordPress Azure Monitor plugin

The image ships with an optional plugin that surfaces sync status and logs inside wp-admin.

## Features
- Admin bar badge showing the current `/home` ↔ `/homelive` sync status.
- "Azure Monitor" menu with a logs page for viewing files under `/home/LogFiles/sync`.
- Buttons to refresh or download logs, plus capability and nonce checks for security.

## Installation
1. Ensure persistent storage is enabled for the site.
2. On container start, the plugin is mirrored from `/opt/wordpress-azure-monitor` to `/home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor`. No manual copy is required.
3. Activate the plugin:
   - Set `WAZM_AUTO_ACTIVATE=1` in App Settings for automatic activation at startup, **or**
   - Activate manually with WP‑CLI: `wp plugin activate wordpress-azure-monitor`, **or**
   - Reinstall and activate in one step: `wp-azure-tools plugin-reinstall -a`.

Once active, administrators see a status badge in the admin bar and can browse logs via **Azure Monitor** in the dashboard.
