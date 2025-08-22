<?php
use PHPUnit\Framework\TestCase;

class StatusTest extends WP_UnitTestCase {
    private string $file = '/home/syncstatus';

    public function tearDown(): void {
        if (file_exists($this->file)) {
            unlink($this->file);
        }
        WAZM_Status::clear_cache();
        parent::tearDown();
    }

    public function test_completed_status_from_file() {
        file_put_contents($this->file, "sync completed\n");
        WAZM_Status::clear_cache();
        $status = WAZM_Status::get_sync_status();
        $this->assertSame('Completed', $status['label']);
        $this->assertSame('green', $status['color']);
    }

    public function test_cache_is_used_until_cleared() {
        file_put_contents($this->file, "sync completed\n");
        WAZM_Status::clear_cache();
        $first = WAZM_Status::get_sync_status();
        $this->assertSame('Completed', $first['label']);

        file_put_contents($this->file, "sync disabled\n");
        $cached = WAZM_Status::get_sync_status();
        $this->assertSame('Completed', $cached['label']);

        WAZM_Status::clear_cache();
        $updated = WAZM_Status::get_sync_status();
        $this->assertSame('Disabled', $updated['label']);
    }
}
