import Foundation

/// A single league announcement surfaced on the Landing page's
/// `AnnouncementsCard`.
///
/// v2 (announcements feature): backed by Supabase `league_announcements`
/// table via the public `GET /announcements` endpoint and the four
/// admin CRUD endpoints. `LeagueAnnouncements.current` is retained as
/// a fallback array for when the public read fails — the Landing page
/// never blanks (acceptance criterion).
///
/// `expiresAt` is consulted at render time — entries past their
/// expiry are filtered out by `AnnouncementsCard`. `nil` means the
/// entry is permanent until removed manually.
///
/// `displayOrder` is a secondary sort key behind priority (critical
/// first), used by the admin to nudge ordering within a priority
/// bucket without changing the priority itself.
struct LeagueAnnouncement: Identifiable, Sendable, Hashable, Codable {
    enum Priority: String, Sendable, Codable, CaseIterable {
        case critical
        case info

        /// Unknown / unrecognised wire string → default to `.info`.
        /// Keeps the decoder resilient if the backend adds a new
        /// priority before the iOS app rolls out support.
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = (try? container.decode(String.self)) ?? "info"
            self = Priority(rawValue: raw) ?? .info
        }
    }

    let id: UUID
    let title: String
    let body: String
    let priority: Priority
    /// Hard cutoff — when `Date() >= expiresAt`, the entry is filtered
    /// out by the card. `nil` = always visible.
    let expiresAt: Date?
    /// True when the row is visible to non-admin readers. Admin list
    /// surfaces all rows regardless. Public read only returns rows
    /// where `is_active = true`.
    let isActive: Bool
    /// Secondary sort key behind priority. Lower numbers float to the
    /// top of a priority bucket. Defaults to 0 for fallback rows.
    let displayOrder: Int
    /// Server timestamps — informational only on the admin list, not
    /// rendered on the public card.
    let createdAt: Date?
    let updatedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        priority: Priority,
        expiresAt: Date? = nil,
        isActive: Bool = true,
        displayOrder: Int = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.priority = priority
        self.expiresAt = expiresAt
        self.isActive = isActive
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case priority
        case expiresAt = "expires_at"
        case isActive = "is_active"
        case displayOrder = "display_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` may arrive as a UUID string; default to a fresh one on
        // decode failure to avoid crashing the list — the row is still
        // displayable, just not addressable by stable id.
        if let raw = try? c.decode(String.self, forKey: .id),
           let uuid = UUID(uuidString: raw) {
            self.id = uuid
        } else {
            self.id = UUID()
        }
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.body = (try? c.decode(String.self, forKey: .body)) ?? ""
        self.priority = (try? c.decode(Priority.self, forKey: .priority)) ?? .info
        self.expiresAt = Self.decodeISODate(c, key: .expiresAt)
        self.isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
        self.displayOrder = (try? c.decode(Int.self, forKey: .displayOrder)) ?? 0
        self.createdAt = Self.decodeISODate(c, key: .createdAt)
        self.updatedAt = Self.decodeISODate(c, key: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id.uuidString, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(priority.rawValue, forKey: .priority)
        try c.encodeIfPresent(expiresAt.map(Self.iso8601Formatter.string(from:)), forKey: .expiresAt)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(displayOrder, forKey: .displayOrder)
        try c.encodeIfPresent(createdAt.map(Self.iso8601Formatter.string(from:)), forKey: .createdAt)
        try c.encodeIfPresent(updatedAt.map(Self.iso8601Formatter.string(from:)), forKey: .updatedAt)
    }

    // MARK: - ISO8601 helpers

    /// Backend writes ISO8601 UTC timestamps. Accept both with and
    /// without fractional seconds (Postgres `timestamptz` can serialise
    /// either way depending on column type). `ISO8601DateFormatter` is
    /// thread-safe for read-only access once configured; the
    /// `nonisolated(unsafe)` annotation acknowledges Swift 6 strict
    /// concurrency without forcing every caller through `@MainActor`.
    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let iso8601FormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func decodeISODate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Date? {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key),
              !raw.isEmpty else { return nil }
        if let date = iso8601Formatter.date(from: raw) {
            return date
        }
        return iso8601FormatterFractional.date(from: raw)
    }
}

/// Hardcoded league announcements used as fallback when the public
/// `/announcements` read fails (acceptance criterion: Landing never
/// blanks). The store uses this list when `announcements.isEmpty` and
/// `error != nil`.
///
/// Filtering + sorting (critical first) happens at render time in
/// `AnnouncementsCard.visible`.
enum LeagueAnnouncements {

    /// Returns the active list as of right now. Use a static `current`
    /// computed property so the dates resolve once per render — there
    /// is no Date mutation cost.
    static var current: [LeagueAnnouncement] {
        [
            LeagueAnnouncement(
                title: "Draft is July 6",
                body: "6:30pm ET sharp. ~1 day per pick. Make sure you can be available for autopick fallback.",
                priority: .critical,
                expiresAt: date(year: 2026, month: 7, day: 7)
            ),
            LeagueAnnouncement(
                title: "Rule Proposals open",
                body: "Vote on this season's open proposals before draft day.",
                priority: .info,
                expiresAt: date(year: 2026, month: 7, day: 6)
            ),
            LeagueAnnouncement(
                title: "Season starts Sept 8",
                body: "Week 1 kicks off Mon Sept 8. Lineups lock at first kickoff.",
                priority: .info,
                expiresAt: date(year: 2026, month: 9, day: 9)
            ),
        ]
    }

    /// Construct a `Date` from y/m/d in the current calendar's local
    /// time zone. Used only for `expiresAt` comparison cutoffs.
    private static func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date.distantFuture
    }
}
