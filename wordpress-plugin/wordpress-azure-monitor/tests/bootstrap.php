<?php
// Load WordPress test environment.
$_tests_dir = getenv('WP_PHPUNIT__DIR');
if (!$_tests_dir) {
    $_tests_dir = dirname(__DIR__) . '/vendor/wp-phpunit/wp-phpunit';
}

require $_tests_dir . '/includes/functions.php';

// Manually load the plugin.
tests_add_filter('muplugins_loaded', function () {
    require dirname(__DIR__) . '/wp-azure-monitor.php';
});

require $_tests_dir . '/includes/bootstrap.php';
