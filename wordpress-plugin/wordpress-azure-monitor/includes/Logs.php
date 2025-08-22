<?php

class WAZM_Logs
{
    /**
     * Cache duration in seconds
     */
    private const CACHE_DURATION = 60; // 1 minute for log metadata

    /**
     * Cache key for whitelisted logs
     */
    private const CACHE_KEY = 'wazm_whitelisted_logs';

    /**
     * Whitelist of allowed log files with strict path validation
     * @return array
     */
    public static function get_whitelisted_logs(): array
    {
        // Try to get from cache first
        $cached = wp_cache_get(self::CACHE_KEY, 'wazm');
        if ($cached !== false) {
            return $cached;
        }

        // Prefer homelive paths (sync-enabled) and fall back to home variants
        $candidates = [
            'apache-access'   => ['/homelive/LogFiles/sync/apache2/access.log', '/home/LogFiles/sync/apache2/access.log'],
            'apache-error'    => ['/homelive/LogFiles/sync/apache2/error.log',  '/home/LogFiles/sync/apache2/error.log'],
            'php-error'       => ['/homelive/LogFiles/sync/apache2/php-error.log','/home/LogFiles/sync/apache2/php-error.log'],
            // Prefer /home for cron since writers append there; include homelive as fallback snapshot
            // If homelive exists and is non-empty, prefer it (sync enabled path)
            'cron'            => ['/homelive/LogFiles/sync/cron.log', '/home/LogFiles/sync/cron.log', '/home/LogFiles/cron.log'],
            // Unison runtime log (written by supervisord program:sync) — prefer homelive
            'sync'            => ['/homelive/LogFiles/sync/unison.log', '/home/LogFiles/sync/unison.log'],
            // Supervisord master log (support both roots)
            'supervisord'     => ['/home/LogFiles/supervisord.log', '/homelive/LogFiles/supervisord.log'],
        ];

        // Resolve latest per-run sync-init logs without relying on symlinks
        $latestSyncInit = self::find_latest_run([
            '/home/LogFiles/sync/runs/sync-init-*.log',
            '/homelive/LogFiles/sync/runs/sync-init-*.log',
        ]);
        if ($latestSyncInit !== null) {
            $candidates['sync-init'] = [$latestSyncInit];
        } else {
            // Fallback to legacy symlinks if scan fails
            $candidates['sync-init'] = ['/homelive/LogFiles/sync-init.log', '/home/LogFiles/sync-init.log'];
        }

        $latestSyncInitErr = self::find_latest_run([
            '/home/LogFiles/sync/runs/sync-init-error-*.log',
            '/homelive/LogFiles/sync/runs/sync-init-error-*.log',
        ]);
        if ($latestSyncInitErr !== null) {
            $candidates['sync-init-error'] = [$latestSyncInitErr];
        } else {
            $candidates['sync-init-error'] = ['/homelive/LogFiles/sync-init-error.log', '/home/LogFiles/sync-init-error.log'];
        }

        $labels = [
            'apache-access' => 'Apache Access',
            'apache-error' => 'Apache Error',
            'php-error' => 'PHP Error',
            'cron' => 'Cron',
            'sync' => 'Sync',
            'supervisord' => 'Supervisord',
            'sync-init' => 'Sync Init',
            'sync-init-error' => 'Sync Init (stderr)',
        ];

        $map = [];
        foreach ($candidates as $key => $paths) {
            foreach ($paths as $p) {
                if ($key === 'cron') {
                    // For cron, require non-empty file to avoid preferring a 0B placeholder
                    if (is_file($p) && is_readable($p)) {
                        $size = filesize($p);
                        if ($size !== false && $size === 0) {
                            continue;
                        }
                    }
                }
                if (is_file($p) && is_readable($p)) {
                    $map[$key] = [
                        'label' => $labels[$key],
                        'path' => $p,
                    ];
                    break; // prefer the first existing candidate
                }
            }
        }

        // Only include files that exist and are readable
        foreach ($map as $key => $meta) {
            if (!is_file($meta['path']) || !is_readable($meta['path'])) {
                unset($map[$key]);
                continue;
            }

            // Check file size (max 50MB)
            $size = filesize($meta['path']);
            if ($size === false || $size > 50 * 1024 * 1024) {
                unset($map[$key]);
                continue;
            }
        }

        // Cache the result
        wp_cache_set(self::CACHE_KEY, $map, 'wazm', self::CACHE_DURATION);

        return $map;
    }

    /**
     * Find the most recent file matching any of the provided glob patterns.
     * Returns null if none found or unreadable.
     */
    private static function find_latest_run(array $patterns): ?string
    {
        $candidates = [];
        foreach ($patterns as $pattern) {
            $matches = glob($pattern) ?: [];
            foreach ($matches as $m) {
                if (is_file($m) && is_readable($m)) {
                    $mtime = @filemtime($m) ?: 0;
                    $candidates[$m] = $mtime;
                }
            }
        }

        if (empty($candidates)) {
            return null;
        }

        arsort($candidates, SORT_NUMERIC);
        $best = array_key_first($candidates);
        return $best ?: null;
    }

    /**
     * Safely read the tail of a log file
     * @param string $path
     * @param int $lines
     * @return string
     */
    public static function tail_file(string $path, int $lines = 500): string
    {
        // Validate path is in our whitelist
        $allowed_paths = array_column(self::get_whitelisted_logs(), 'path');
        if (!in_array($path, $allowed_paths, true)) {
            return 'Access denied: Invalid log file.';
        }

        if (!is_readable($path)) {
            return 'Log not readable or does not exist.';
        }

        // Limit lines to prevent abuse
        $lines = min(max($lines, 1), 1000);

        try {
            // Use more efficient tail approach
            $content = self::read_file_tail($path, $lines);
            return $content;
        } catch (Exception $e) {
            error_log('WAZM Logs Error: ' . $e->getMessage());
            return 'Error reading log file.';
        }
    }

    /**
     * Efficiently read the tail of a file using reverse reading
     * @param string $path
     * @param int $lines
     * @return string
     */
    private static function read_file_tail(string $path, int $lines): string
    {
        $size = filesize($path);
        if ($size === false || $size === 0) {
            return '';
        }

        // For very small files, just read the whole thing
        if ($size <= 8192) { // 8KB threshold
            $content = file_get_contents($path);
            if ($content === false) {
                return 'Unable to read log file.';
            }

            $rows = preg_split("/\r?\n/", $content);
            $rows = array_slice($rows, -$lines);
            return implode("\n", $rows);
        }

        // For larger files, read from end efficiently
        $fp = fopen($path, 'rb');
        if (!$fp) {
            return 'Unable to open log file.';
        }

        $buffer_size = 4096; // 4KB chunks
        $lines_found = 0;
        $content = '';
        $position = $size;

        // Read backwards from end of file
        while ($position > 0 && $lines_found < $lines) {
            $read_size = min($buffer_size, $position);
            $position -= $read_size;

            fseek($fp, $position);
            $chunk = fread($fp, $read_size);

            if ($chunk === false) {
                break;
            }

            // Prepend chunk to content
            $content = $chunk . $content;

            // Count lines in this chunk
            $lines_found += substr_count($chunk, "\n");
        }

        fclose($fp);

        // Split into lines and get the last N lines
        $rows = preg_split("/\r?\n/", $content);
        $rows = array_slice($rows, -$lines);

        return implode("\n", $rows);
    }

    /**
     * Clear logs cache (call when log files change)
     */
    public static function clear_cache(): void
    {
        wp_cache_delete(self::CACHE_KEY, 'wazm');
    }
}
