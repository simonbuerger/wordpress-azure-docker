<?php

class WAZM_Status
{
    /**
     * Cache duration in seconds
     */
    private const CACHE_DURATION = 30; // 30 seconds

    /**
     * Cache key for status
     */
    private const CACHE_KEY = 'wazm_sync_status';

    /**
     * Get sync status with caching and proper security validation
     * @return array
     */
    public static function get_sync_status(): array
    {
        // Try to get from cache first
        $cached = wp_cache_get(self::CACHE_KEY, 'wazm');
        if ($cached !== false) {
            return $cached;
        }

        $status = self::read_sync_status();

        // Cache the result
        wp_cache_set(self::CACHE_KEY, $status, 'wazm', self::CACHE_DURATION);

        return $status;
    }

    /**
     * Read sync status from file
     * @return array
     */
    private static function read_sync_status(): array
    {
        $label = 'Initializing';
        $color = 'yellow';

        $file = '/home/syncstatus';

        if (!is_file($file)) {
            return ['label' => $label, 'color' => $color];
        }

        // Check if file is readable and not too large
        if (!is_readable($file)) {
            error_log('WAZM Status: Status file not readable: ' . $file);
            return ['label' => 'Error', 'color' => 'red', 'error' => 'Status file not accessible'];
        }

        $file_size = filesize($file);
        if ($file_size === false || $file_size > 4096) { // Max 4KB safety
            error_log('WAZM Status: Status file too large or unreadable: ' . $file);
            return ['label' => 'Error', 'color' => 'red', 'error' => 'Invalid status file'];
        }

        try {
            $handle = fopen($file, 'r');
            if (!$handle) {
                error_log('WAZM Status: Unable to open status file: ' . $file);
                return ['label' => 'Error', 'color' => 'red', 'error' => 'Unable to read status'];
            }

            // Read first line
            $line = fgets($handle);
            fclose($handle);

            if ($line === false) {
                return ['label' => $label, 'color' => $color];
            }

            // Normalize
            $line = trim($line);

            // Parse status safely (consider only the prefix before any colon/timestamp)
            $status = self::parse_status_line($line);
            return $status;

        } catch (Exception $e) {
            error_log('WAZM Status Error: ' . $e->getMessage());
            return ['label' => 'Error', 'color' => 'red', 'error' => 'Status read error'];
        }
    }

    /**
     * Clear status cache (call when status changes)
     */
    public static function clear_cache(): void
    {
        wp_cache_delete(self::CACHE_KEY, 'wazm');
    }

    /**
     * Parse status line safely
     * @param string $line
     * @return array
     */
    private static function parse_status_line(string $line): array
    {
        $line_lower = strtolower($line);
        // Consider only the status phrase before any colon (e.g., "sync completed: Wed ...")
        $prefix = $line_lower;
        $colonPos = strpos($line_lower, ':');
        if ($colonPos !== false) {
            $prefix = substr($line_lower, 0, $colonPos);
        }

        if (strpos($prefix, 'sync disabled') !== false) {
            return ['label' => 'Disabled', 'color' => 'red'];
        }
        if (strpos($prefix, 'sync error') !== false) {
            return ['label' => 'Error', 'color' => 'red'];
        }
        if (strpos($prefix, 'sync completed') !== false) {
            return ['label' => 'Completed', 'color' => 'green'];
        }
        if (strpos($prefix, 'sync enabled') !== false) {
            return ['label' => 'Enabled', 'color' => 'green'];
        }
        if (strpos($prefix, 'sync running') !== false) {
            return ['label' => 'Running', 'color' => 'blue'];
        }

        return ['label' => 'Initializing', 'color' => 'yellow'];
    }
}
