<?php
/**
 * Plugin Name: WordPress Azure Monitor
 * Description: Shows Azure sync status in the admin bar and provides a logs dashboard for /home/LogFiles/sync.
 * Version: 0.1.5
 * Author: Blugrass Digital
 * Security: Enhanced with comprehensive input validation and output sanitization
 * Performance: Optimized with efficient log tailing and intelligent caching
 */

if (!defined('ABSPATH')) {
    exit;
}

// Security: Add nonce constant
if (!defined('WAZM_NONCE_ACTION')) {
    define('WAZM_NONCE_ACTION', 'wazm_admin_action');
}

// PSR-4-ish minimal autoload
spl_autoload_register(function ($class) {
    if (strpos($class, 'WAZM_') === 0) {
        $rel = str_replace('WAZM_', '', $class);
        $rel = str_replace('\\', '/', $rel);
        $path = __DIR__ . '/includes/' . $rel . '.php';
        if (is_file($path)) {
            require_once $path;
        }
    }
});

// Enqueue admin styles
add_action('admin_enqueue_scripts', function () {
    wp_register_style('wazm-admin', plugins_url('assets/admin.css', __FILE__), [], '0.1.3');
    wp_enqueue_style('wazm-admin');
});

// Also load styles on the front-end when the admin bar shows
add_action('wp_enqueue_scripts', function () {
    if (is_user_logged_in() && is_admin_bar_showing()) {
        wp_register_style('wazm-admin', plugins_url('assets/admin.css', __FILE__), [], '0.1.3');
        wp_enqueue_style('wazm-admin');
    }
});

// Admin bar status badge
add_action('admin_bar_menu', function (WP_Admin_Bar $admin_bar) {
    if (!current_user_can('manage_options')) {
        return;
    }

    try {
        $status = WAZM_Status::get_sync_status();

        $label = sanitize_text_field($status['label'] ?? '');
        // Hide only when explicitly Disabled
        if (strcasecmp($label, 'Disabled') === 0) {
            return;
        }

        $color = sanitize_html_class($status['color'] ?? 'yellow');

        $admin_bar->add_node([
            'id'    => 'wazm-sync-status',
            'title' => sprintf('<span class="wazm-badge wazm-badge--%s">%s</span>', $color, $label),
            'href'  => admin_url('admin.php?page=wazm-logs'),
            'meta'  => ['html' => true],
        ]);
    } catch (Exception $e) {
        error_log('WAZM Admin Bar Error: ' . $e->getMessage());
    }
}, 100);

// Menu + page
add_action('admin_menu', function () {
    if (!current_user_can('manage_options')) {
        return;
    }
    add_menu_page(
        'Azure Monitor',
        'Azure Monitor',
        'manage_options',
        'wazm-logs',
        'wazm_render_logs_page',
        'dashicons-visibility',
        65
    );
});

/**
 * Render the logs page with proper security
 */
function wazm_render_logs_page()
{
    if (!current_user_can('manage_options')) {
        wp_die(__('You do not have sufficient permissions to access this page.'));
    }

    // Clear cache on page load to ensure fresh data
    WAZM_Status::clear_cache();
    WAZM_Logs::clear_cache();

    // Verify nonce for form submission
    if (isset($_GET['log']) && !wp_verify_nonce($_GET['_wpnonce'] ?? '', WAZM_NONCE_ACTION)) {
        wp_die(__('Security check failed.'));
    }

    wp_enqueue_style('wazm-admin');

    try {
        $allowed = WAZM_Logs::get_whitelisted_logs();

        if (empty($allowed)) {
            echo '<div class="wrap">';
            echo '<h1>' . esc_html__('Azure Monitor Logs') . '</h1>';
            echo '<div class="notice notice-error"><p>' . esc_html__('No valid log files found or access denied.') . '</p></div>';
            echo '</div>';
            return;
        }

        $selected_key = isset($_GET['log']) ? sanitize_key($_GET['log']) : key($allowed);
        if (!isset($allowed[$selected_key])) {
            $selected_key = key($allowed);
        }

        $file_path = $allowed[$selected_key]['path'];
        $content = WAZM_Logs::tail_file($file_path, 500);
        $mtime = @filemtime($file_path);

        echo '<div class="wrap">';
        echo '<h1>' . esc_html__('Azure Monitor Logs') . '</h1>';

        // Log selector form with refresh button
        echo '<form method="get" action="" style="margin: 1em 0;">';
        echo '<input type="hidden" name="page" value="wazm-logs" />';
        echo '<input type="hidden" name="_wpnonce" value="' . esc_attr(wp_create_nonce(WAZM_NONCE_ACTION)) . '" />';
        echo '<label for="wazm-log-select">' . esc_html__('Select log:') . ' </label>';
        echo '<select name="log" id="wazm-log-select">';

        foreach ($allowed as $key => $meta) {
            $selected = selected($selected_key, $key, false);
            printf(
                '<option value="%s" %s>%s</option>',
                esc_attr($key),
                $selected,
                esc_html($meta['label'])
            );
        }

        echo '</select> ';
        submit_button(__('View'), 'secondary', '', false);
        echo '&nbsp;';

        // Refresh button
        $refresh_url = wp_nonce_url(
            admin_url('admin.php?page=wazm-logs&refresh=1'),
            WAZM_NONCE_ACTION
        );
        echo '<a class="button" href="' . esc_url($refresh_url) . '">' . esc_html__('Refresh') . '</a>';
        echo '&nbsp;';

        // Download button
        if (is_readable($file_path)) {
            $dl_url = wp_nonce_url(
                admin_url('admin-ajax.php?action=wazm_download_log&log=' . urlencode($selected_key)),
                'wazm_log'
            );
            echo '<a class="button" href="' . esc_url($dl_url) . '">' . esc_html__('Download') . '</a>';
        }

        echo '</form>';

        // Status display
        $status = WAZM_Status::get_sync_status();
        $status_class = sanitize_html_class($status['color']);
        $status_label = esc_html($status['label']);

        echo '<p>' . esc_html__('Sync status:') . ' <span class="wazm-badge wazm-badge--' . $status_class . '">' . $status_label . '</span></p>';

        // Error display if any
        if (isset($status['error'])) {
            echo '<div class="notice notice-error"><p>' . esc_html($status['error']) . '</p></div>';
        }

        if (!is_readable($file_path)) {
            echo '<p><em>' . esc_html__('Log is not readable:') . ' ' . esc_html($file_path) . '</em></p>';
        } else {
            $file_info = sprintf(
                __('File: %s • Updated: %s'),
                esc_html($file_path),
                $mtime ? esc_html(date('Y-m-d H:i:s', $mtime)) : 'n/a'
            );
            echo '<p><small>' . $file_info . '</small></p>';

            // Display log content safely
            echo '<pre class="wazm-log">' . esc_html($content) . '</pre>';
        }

        echo '</div>';

    } catch (Exception $e) {
        error_log('WAZM Logs Page Error: ' . $e->getMessage());
        echo '<div class="wrap">';
        echo '<h1>' . esc_html__('Azure Monitor Logs') . '</h1>';
        echo '<div class="notice notice-error"><p>' . esc_html__('An error occurred while loading the logs.') . '</p></div>';
        echo '</div>';
    }
}

// Download endpoint with enhanced security
add_action('wp_ajax_wazm_download_log', function () {
    if (!current_user_can('manage_options')) {
        wp_die(__('You do not have sufficient permissions to access this page.'), 403);
    }

    if (!check_admin_referer('wazm_log')) {
        wp_die(__('Security check failed.'), 403);
    }

    try {
        $allowed = WAZM_Logs::get_whitelisted_logs();
        $selected_key = isset($_GET['log']) ? sanitize_key($_GET['log']) : '';

        if (!isset($allowed[$selected_key])) {
            wp_die(__('Invalid log file.'), 400);
        }

        $file = $allowed[$selected_key]['path'];

        // Additional security check
        if (!in_array($file, array_column($allowed, 'path'))) {
            wp_die(__('Access denied.'), 403);
        }

        if (!is_readable($file)) {
            wp_die(__('Log file not readable.'), 404);
        }

        // Check file size limit (max 10MB for download)
        $file_size = filesize($file);
        if ($file_size === false || $file_size > 10 * 1024 * 1024) {
            wp_die(__('File too large for download.'), 413);
        }

        // Set headers for download
        header('Content-Type: text/plain; charset=utf-8');
        header('Content-Disposition: attachment; filename="' . basename($file) . '"');
        header('Content-Length: ' . $file_size);
        header('Cache-Control: no-cache, must-revalidate');
        header('Expires: Sat, 26 Jul 1997 05:00:00 GMT');

        // Read and output file safely
        $handle = fopen($file, 'rb');
        if ($handle) {
            while (!feof($handle)) {
                $buffer = fread($handle, 8192);
                if ($buffer === false) {
                    break;
                }
                echo $buffer;
            }
            fclose($handle);
        }

        exit;

    } catch (Exception $e) {
        error_log('WAZM Download Error: ' . $e->getMessage());
        wp_die(__('An error occurred during download.'), 500);
    }
});
