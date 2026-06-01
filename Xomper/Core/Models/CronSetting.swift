import Foundation

/// One row from the Supabase `admin_cron_settings` table — surfaced via
/// `GET /admin/cron-settings-list` (admin-cron-settings F1). Each row
/// represents a single scheduled notification lambda; the admin can
/// flip `enabled` to no-op the cron entirely or `testMode` to restrict
/// delivery to the admin's Sleeper user only (for newsletter previews).
///
/// JSON shape (snake_case from the backend):
/// ```json
/// {
///   "cron_key": "notif_weekly_recap",
///   "enabled": true,
///   "test_mode": false,
///   "description": "Weekly matchup recap — Tue 9am ET",
///   "updated_at": "2026-06-01T14:30:00Z"
/// }
/// ```
///
/// `description` may be absent for new rows the admin hasn't yet
/// labelled (defensive). `updatedAt` is decoded via the shared
/// `AIReport.parseISO` so it tolerates both the fractional-seconds and
/// integer-seconds ISO 8601 variants Supabase emits.
struct CronSetting: Codable, Sendable, Identifiable, Hashable {
    let cronKey: String
    let enabled: Bool
    let testMode: Bool
    let description: String?
    let updatedAt: Date?

    /// `cronKey` is unique in the table — Supabase enforces it as the
    /// primary key — so it doubles as the SwiftUI Identifiable hook.
    var id: String { cronKey }

    enum CodingKeys: String, CodingKey {
        case cronKey = "cron_key"
        case enabled
        case testMode = "test_mode"
        case description
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.cronKey = (try? c.decode(String.self, forKey: .cronKey)) ?? ""
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        self.testMode = (try? c.decode(Bool.self, forKey: .testMode)) ?? false
        self.description = try? c.decodeIfPresent(String.self, forKey: .description)

        if let raw = try? c.decodeIfPresent(String.self, forKey: .updatedAt),
           let parsed = AIReport.parseISO(raw) {
            self.updatedAt = parsed
        } else {
            self.updatedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cronKey, forKey: .cronKey)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(testMode, forKey: .testMode)
        try c.encodeIfPresent(description, forKey: .description)
        if let updatedAt {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try c.encode(iso.string(from: updatedAt), forKey: .updatedAt)
        }
    }

    /// Memberwise init for tests / previews. The decoder uses the
    /// throwing init above; this overload sidesteps that for in-memory
    /// fixtures.
    init(
        cronKey: String,
        enabled: Bool,
        testMode: Bool,
        description: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.cronKey = cronKey
        self.enabled = enabled
        self.testMode = testMode
        self.description = description
        self.updatedAt = updatedAt
    }

    /// Title rendered in `CronSettingsView`'s rows. Prefer the
    /// human-friendly `description`; fall back to the `cron_key` so a
    /// freshly-seeded row without a description still shows something
    /// readable.
    var displayTitle: String {
        if let description, !description.isEmpty {
            return description
        }
        return cronKey
    }

    /// Returns a copy with `enabled` swapped. Used by the store for
    /// optimistic UI updates before the network call resolves.
    func with(enabled newEnabled: Bool) -> CronSetting {
        CronSetting(
            cronKey: cronKey,
            enabled: newEnabled,
            testMode: testMode,
            description: description,
            updatedAt: updatedAt
        )
    }

    /// Returns a copy with `testMode` swapped. Used by the store for
    /// optimistic UI updates before the network call resolves.
    func with(testMode newTestMode: Bool) -> CronSetting {
        CronSetting(
            cronKey: cronKey,
            enabled: enabled,
            testMode: newTestMode,
            description: description,
            updatedAt: updatedAt
        )
    }
}
