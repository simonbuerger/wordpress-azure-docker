<?php

class LogsTest extends WP_UnitTestCase {
    private string $logDir = '/home/LogFiles/sync/apache2';

    public function setUp(): void {
        parent::setUp();
        wp_mkdir_p($this->logDir);
    }

    public function tearDown(): void {
        if (is_dir('/home/LogFiles')) {
            // Cleanup created log directories and files.
            $this->rmdir_recursive('/home/LogFiles');
        }
        WAZM_Logs::clear_cache();
        parent::tearDown();
    }

    private function rmdir_recursive($dir) {
        if (!is_dir($dir)) {
            return;
        }
        $items = scandir($dir);
        foreach ($items as $item) {
            if ($item === '.' || $item === '..') {
                continue;
            }
            $path = $dir . '/' . $item;
            if (is_dir($path)) {
                $this->rmdir_recursive($path);
            } else {
                unlink($path);
            }
        }
        rmdir($dir);
    }

    public function test_whitelist_includes_existing_log() {
        $path = $this->logDir . '/error.log';
        file_put_contents($path, 'sample');
        $logs = WAZM_Logs::get_whitelisted_logs();
        $this->assertArrayHasKey('apache-error', $logs);
        $this->assertSame($path, $logs['apache-error']['path']);
    }

    public function test_download_endpoint_outputs_log() {
        $path = $this->logDir . '/error.log';
        file_put_contents($path, 'downloaded');

        $script = escapeshellarg(__DIR__ . '/run-download.php');
        $output = shell_exec(PHP_BINARY . " $script apache-error");
        $this->assertSame('downloaded', trim($output));
    }
}
