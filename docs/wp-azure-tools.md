# wp-azure-tools CLI

`wp-azure-tools` is a maintenance helper available inside the container for common operational tasks.

## Usage
```
wp-azure-tools <command> [options]
```

## Commands
- `status` – show environment and path information.
- `plugin-reinstall [-a]` – reinstall the bundled Azure Monitor plugin; use `-a` to activate.
- `rotate-logs` – force logrotate for Apache logs.
- `fix-perms [path]` – run the permission fix script (defaults to live docroot).
- `ensure-uploads` – ensure the live uploads symlink points to persisted uploads.
- `run-cron [home|homelive]` – run WordPress cron events due now.
- `seed-logs` – rotate then seed logs from `/home` to `/homelive`.
- `seed-content` – seed code and wp-content (excluding uploads) between trees.
- `bootstrap-core [-f]` – download or refresh WordPress core (use `-f` to force).
- `bootstrap-config [-f]` – create or refresh `wp-config.php` (use `-f` to overwrite).

## Examples
```
wp-azure-tools status
wp-azure-tools plugin-reinstall -a
wp-azure-tools run-cron homelive
```
