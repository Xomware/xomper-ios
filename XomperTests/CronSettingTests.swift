import XCTest
@testable import Xomper

/// admin-cron-settings — verifies `CronSetting` decodes the wire shape
/// returned by `GET /admin/cron-settings-list` (snake_case ↔ camelCase),
/// tolerates missing optional fields, and that `CronSettingsListResponse`
/// surfaces the `table_missing` empty-state signal cleanly.
@MainActor
final class CronSettingTests: XCTestCase {

    // MARK: - CronSetting

    func test_cronSetting_decodesFullPayload() throws {
        let json = """
        {
            "cron_key": "notif_weekly_recap",
            "enabled": true,
            "test_mode": false,
            "description": "Weekly matchup recap — Tue 9am ET",
            "updated_at": "2026-06-01T14:30:00Z"
        }
        """
        let setting = try JSONDecoder().decode(
            CronSetting.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(setting.cronKey, "notif_weekly_recap")
        XCTAssertTrue(setting.enabled)
        XCTAssertFalse(setting.testMode)
        XCTAssertEqual(setting.description, "Weekly matchup recap — Tue 9am ET")
        XCTAssertNotNil(setting.updatedAt)
        XCTAssertEqual(setting.id, "notif_weekly_recap", "id should mirror cron_key")
    }

    func test_cronSetting_missingOptionalFields() throws {
        let json = """
        {
            "cron_key": "notif_lineup_not_set",
            "enabled": false,
            "test_mode": true
        }
        """
        let setting = try JSONDecoder().decode(
            CronSetting.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(setting.cronKey, "notif_lineup_not_set")
        XCTAssertFalse(setting.enabled)
        XCTAssertTrue(setting.testMode)
        XCTAssertNil(setting.description)
        XCTAssertNil(setting.updatedAt)
    }

    func test_cronSetting_fractionalSecondsTimestamp() throws {
        let json = """
        {
            "cron_key": "notif_close_game_alert",
            "enabled": true,
            "test_mode": false,
            "updated_at": "2026-06-01T14:30:00.123Z"
        }
        """
        let setting = try JSONDecoder().decode(
            CronSetting.self,
            from: Data(json.utf8)
        )
        XCTAssertNotNil(setting.updatedAt, "Fractional-seconds ISO 8601 timestamp should decode.")
    }

    func test_cronSetting_displayTitleFallsBackToCronKey() {
        let setting = CronSetting(
            cronKey: "notif_misc",
            enabled: true,
            testMode: false,
            description: nil
        )
        XCTAssertEqual(setting.displayTitle, "notif_misc")
    }

    func test_cronSetting_displayTitlePrefersDescription() {
        let setting = CronSetting(
            cronKey: "notif_misc",
            enabled: true,
            testMode: false,
            description: "Friendly label"
        )
        XCTAssertEqual(setting.displayTitle, "Friendly label")
    }

    func test_cronSetting_withEnabledFlipsCorrectly() {
        let original = CronSetting(
            cronKey: "x",
            enabled: true,
            testMode: true,
            description: "Desc"
        )
        let flipped = original.with(enabled: false)
        XCTAssertFalse(flipped.enabled)
        XCTAssertTrue(flipped.testMode, "testMode preserved on enabled flip")
        XCTAssertEqual(flipped.description, "Desc")
    }

    func test_cronSetting_withTestModeFlipsCorrectly() {
        let original = CronSetting(
            cronKey: "x",
            enabled: true,
            testMode: false,
            description: "Desc"
        )
        let flipped = original.with(testMode: true)
        XCTAssertTrue(flipped.testMode)
        XCTAssertTrue(flipped.enabled, "enabled preserved on testMode flip")
    }

    // MARK: - CronSettingsListResponse

    func test_listResponse_decodesFullPayload() throws {
        let json = """
        {
            "Success": true,
            "count": 2,
            "rows": [
                {
                    "cron_key": "notif_weekly_recap",
                    "enabled": true,
                    "test_mode": false,
                    "description": "Weekly recap",
                    "updated_at": "2026-06-01T14:30:00Z"
                },
                {
                    "cron_key": "notif_lineup_not_set",
                    "enabled": false,
                    "test_mode": true,
                    "description": "Lineup not set",
                    "updated_at": "2026-06-01T14:30:00Z"
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(
            CronSettingsListResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.rows.count, 2)
        XCTAssertEqual(response.rows.first?.cronKey, "notif_weekly_recap")
        XCTAssertFalse(response.tableMissing)
    }

    func test_listResponse_tableMissingTrue() throws {
        let json = """
        {
            "Success": true,
            "count": 0,
            "rows": [],
            "table_missing": true
        }
        """
        let response = try JSONDecoder().decode(
            CronSettingsListResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(response.tableMissing)
        XCTAssertEqual(response.rows.count, 0)
        XCTAssertEqual(response.count, 0)
    }

    func test_listResponse_tableMissingAbsentDefaultsFalse() throws {
        let json = """
        {
            "Success": true,
            "count": 0,
            "rows": []
        }
        """
        let response = try JSONDecoder().decode(
            CronSettingsListResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertFalse(response.tableMissing)
    }

    // MARK: - CronSettingUpdateResponse

    func test_updateResponse_decodesPayload() throws {
        let json = """
        {
            "Success": true,
            "cron_key": "notif_weekly_recap",
            "enabled": false,
            "test_mode": true
        }
        """
        let response = try JSONDecoder().decode(
            CronSettingUpdateResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.cronKey, "notif_weekly_recap")
        XCTAssertFalse(response.enabled)
        XCTAssertTrue(response.testMode)
    }
}
