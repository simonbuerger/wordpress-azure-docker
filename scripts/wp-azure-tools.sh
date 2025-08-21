#!/usr/bin/env bash

# WordPress Azure maintenance helper
#
# Provides handy one-liners for common hygiene tasks inside the container.
# Usage:
#   wp-azure-tools <command> [options]
#
# Commands:
#   status                       Show environment/paths summary
#   plugin-reinstall [-a]        Reinstall bundled Azure Monitor plugin; -a to activate
#   rotate-logs                  Force logrotate for Apache logs
#   fix-perms [path]             Run fix-wordpress-permissions on path (default: live docroot)
#   ensure-uploads               Ensure /homelive uploads symlink → /home uploads
#   run-cron [home|homelive]     Run WP cron due-now in selected tree (defaults based on DOCKER_SYNC_ENABLED)
#   seed-logs                    Rotate then seed logs from /home to /homelive
#   seed-content                 Seed code and wp-content (excl. uploads) from /home to /homelive
#
# Notes:
# - Safe by default; commands log their actions and continue on minor failures.

set -o pipefail

log_info() { echo "$(date) [INFO] $*"; }
log_warn() { echo "$(date) [WARN] $*"; }
log_error() { echo "$(date) [ERROR] $*"; }

# Resolve live paths based on /home → /homelive rewrite
derive_live_paths() {
	APACHE_DOCUMENT_ROOT_LIVE=$(echo "${APACHE_DOCUMENT_ROOT:-/home/site/wwwroot}" | sed -e "s/\/home\//\/homelive\//g")
	WP_CONTENT_ROOT_LIVE=$(echo "${WP_CONTENT_ROOT:-/home/site/wwwroot/wp-content}" | sed -e "s/\/home\//\/homelive\//g")
	APACHE_LOG_DIR_LIVE=$(echo "${APACHE_LOG_DIR:-/home/LogFiles/sync}" | sed -e "s/\/home\//\/homelive\//g")
}

ensure_symlink() {
	local target="$1"
	local link="$2"
	log_info "ensure_symlink: link='$link' target='$target'"
	if [[ -e "$link" || -L "$link" ]]; then
		if [[ -L "$link" ]]; then
			local current_target
			current_target="$(readlink -f "$link" || true)"
			local resolved_target
			resolved_target="$(readlink -f "$target" || true)"
			if [[ "$current_target" != "$resolved_target" || -z "$current_target" ]]; then
				log_warn "Replacing incorrect/broken symlink ('$current_target') with '$target'"
				rm -f "$link" 2>/dev/null || true
				ln -s "$target" "$link" || true
			else
				log_info "Symlink already correct"
			fi
		else
			log_warn "Replacing existing file/dir at '$link' with symlink to '$target'"
			rm -rf "$link" 2>/dev/null || true
			ln -s "$target" "$link" || true
		fi
	else
		log_info "Creating symlink '$link' -> '$target'"
		ln -s "$target" "$link" || true
	fi
}

cmd_status() {
	derive_live_paths
	cat <<EOF
DOCKER_SYNC_ENABLED=${DOCKER_SYNC_ENABLED:-}
USE_SYSTEM_CRON=${USE_SYSTEM_CRON:-1}
APACHE_DOCUMENT_ROOT=${APACHE_DOCUMENT_ROOT:-/home/site/wwwroot}
APACHE_DOCUMENT_ROOT_LIVE=${APACHE_DOCUMENT_ROOT_LIVE}
WP_CONTENT_ROOT=${WP_CONTENT_ROOT:-/home/site/wwwroot/wp-content}
WP_CONTENT_ROOT_LIVE=${WP_CONTENT_ROOT_LIVE}
APACHE_LOG_DIR=${APACHE_LOG_DIR:-/home/LogFiles/sync}
APACHE_LOG_DIR_LIVE=${APACHE_LOG_DIR_LIVE}
EOF
}

cmd_plugin_reinstall() {
	local activate_flag="$1"
	if [[ ! -d "/opt/wordpress-azure-monitor" ]]; then
		log_error "/opt/wordpress-azure-monitor not found in image"
		return 1
	fi
	derive_live_paths
	log_info "Copying wordpress-azure-monitor to persistent and live paths"
	mkdir -p /home/site/wwwroot/wp-content/plugins "${WP_CONTENT_ROOT_LIVE%/}/plugins"
	rsync -a /opt/wordpress-azure-monitor/ /home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor/ && log_info "Plugin copied to /home" || log_warn "Copy to /home failed"
	rsync -a /opt/wordpress-azure-monitor/ "${WP_CONTENT_ROOT_LIVE%/}/plugins/wordpress-azure-monitor/" && log_info "Plugin copied to /homelive" || log_warn "Copy to /homelive failed"
	if [[ "$activate_flag" == "-a" || "$activate_flag" == "--activate" ]]; then
		log_info "Attempting activation if WP core is installed"
		WP_CLI_ALLOW_ROOT=1 sh -lc "cd '/homelive/site/wwwroot' && wp core is-installed --quiet && wp plugin activate wordpress-azure-monitor --quiet" && log_info "Activated on /homelive" || log_warn "Activation on /homelive skipped/failed"
		WP_CLI_ALLOW_ROOT=1 sh -lc "cd '/home/site/wwwroot' && wp core is-installed --quiet && wp plugin activate wordpress-azure-monitor --quiet" && log_info "Activated on /home" || log_warn "Activation on /home skipped/failed"
	fi
}

cmd_rotate_logs() {
	if logrotate -f /etc/logrotate.d/apache2 >/dev/null 2>&1; then
		log_info "Log rotation forced successfully"
	else
		log_warn "Log rotation failed"
	fi
}

cmd_fix_perms() {
	derive_live_paths
	local target="${1:-$APACHE_DOCUMENT_ROOT_LIVE}"
	log_info "Fixing permissions on '$target'"
	if fix-wordpress-permissions.sh "$target"; then
		log_info "Permissions fixed"
	else
		log_warn "Permission fix script failed"
	fi
}

cmd_ensure_uploads() {
	derive_live_paths
	mkdir -p "${WP_CONTENT_ROOT:-/home/site/wwwroot/wp-content}/uploads"
	mkdir -p "$WP_CONTENT_ROOT_LIVE"
	ensure_symlink "${WP_CONTENT_ROOT:-/home/site/wwwroot/wp-content}/uploads" "${WP_CONTENT_ROOT_LIVE%/}/uploads"
}

cmd_run_cron() {
	local target_tree="$1"
	if [[ -z "$target_tree" ]]; then
		if [[ "${DOCKER_SYNC_ENABLED:-}" == "1" || "${DOCKER_SYNC_ENABLED:-}" == "true" ]]; then
			target_tree="homelive"
		else
			target_tree="home"
		fi
	fi
	local path
	if [[ "$target_tree" == "homelive" ]]; then
		path="/homelive/site/wwwroot"
	else
		path="/home/site/wwwroot"
	fi
	log_info "Running WP cron due-now in $path"
	WP_CLI_ALLOW_ROOT=1 sh -lc "cd '$path' && wp cron event run --due-now" && log_info "WP cron run finished" || log_warn "WP cron run failed"
}

cmd_seed_logs() {
	cmd_rotate_logs
	log_info "Seeding logs: /home/LogFiles -> /homelive/LogFiles"
	rsync -apoghW --no-compress /home/LogFiles/ /homelive/LogFiles/ --exclude '*.unison.tmp' && log_info "Logs seeded" || log_warn "Log seeding failed"
}

cmd_seed_content() {
	derive_live_paths
	log_info "Seeding code: /home/site/wwwroot -> /homelive/site/wwwroot (excluding wp-content)"
	rsync -apoghW --no-compress /home/site/wwwroot/ /homelive/site/wwwroot/ --exclude 'wp-content' --exclude '*.unison.tmp' --chown "www-data:www-data" --chmod "D0755,F0644" && log_info "Code seeded" || log_warn "Code seeding failed"
	log_info "Seeding wp-content: ${WP_CONTENT_ROOT:-/home/site/wwwroot/wp-content} -> $WP_CONTENT_ROOT_LIVE (excluding uploads)"
	rsync -apoghW --no-compress "${WP_CONTENT_ROOT:-/home/site/wwwroot/wp-content}/" "$WP_CONTENT_ROOT_LIVE/" --exclude 'uploads' --exclude '*.unison.tmp' --chown "www-data:www-data" --chmod "D0775,F0664" && log_info "wp-content seeded" || log_warn "wp-content seeding failed"
}

usage() {
	cat <<EOF
Usage: wp-azure-tools <command> [options]

Commands:
  status                       Show environment/paths summary
  plugin-reinstall [-a]        Reinstall bundled Azure Monitor plugin; -a to activate
  rotate-logs                  Force logrotate for Apache logs
  fix-perms [path]             Fix permissions (default: live docroot)
  ensure-uploads               Ensure live uploads symlink -> persisted uploads
  run-cron [home|homelive]     Run WP cron due-now in selected tree
  seed-logs                    Rotate then seed logs from /home to /homelive
  seed-content                 Seed code and wp-content (excl. uploads) to /homelive

Examples:
  wp-azure-tools plugin-reinstall -a
  wp-azure-tools run-cron homelive
  wp-azure-tools fix-perms /homelive/site/wwwroot
EOF
}

main() {
	case "${1:-}" in
		status) shift; cmd_status "$@" ;;
		plugin-reinstall) shift; cmd_plugin_reinstall "${1:-}" ;;
		rotate-logs) shift; cmd_rotate_logs ;;
		fix-perms) shift; cmd_fix_perms "${1:-}" ;;
		ensure-uploads) shift; cmd_ensure_uploads ;;
		run-cron) shift; cmd_run_cron "${1:-}" ;;
		seed-logs) shift; cmd_seed_logs ;;
		seed-content) shift; cmd_seed_content ;;
		-h|--help|help|"") usage ;;
		*) log_error "Unknown command: $1"; usage; return 1 ;;
	 esac
}

main "$@"


