<?php
require __DIR__ . '/bootstrap.php';

$log_key = $argv[1];

// Create admin user and authenticate.
$user_id = wp_create_user('admin', 'password', 'admin@example.com');
$user = new WP_User($user_id);
$user->set_role('administrator');
wp_set_current_user($user_id);

// Prepare request variables.
$_GET['log'] = $log_key;
$_GET['action'] = 'wazm_download_log';
$_REQUEST['_wpnonce'] = wp_create_nonce('wazm_log');

do_action('wp_ajax_wazm_download_log');
