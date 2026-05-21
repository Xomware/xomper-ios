import Foundation

/// A single league announcement surfaced on the Landing page's
/// `AnnouncementsCard`. v1 is a hardcoded list (see
/// `LeagueAnnouncements.current` below); v2 may move this to Supabase.
///
/// `expiresAt` is consulted at render time — entries past their
/// expiry are filtered out by `AnnouncementsCard`. `nil` means the
/// entry is permanent until removed manually.
struct LeagueAnnouncement: Identifiable, Sendable {
    enum Priority: Sendable {
        case critical
        case info
    }

    let id: UUID
    let title: String
    let body: String
    let priority: Priority
    /// Hard cutoff — when `Date() >= expiresAt`, the entry is filtered
    /// out by the card. `nil` = always visible.
    let expiresAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        priority: Priority,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.priority = priority
        self.expiresAt = expiresAt
    }
}

/// Hardcoded league announcements for v1. Edit this array to add or
/// retire entries — there is no admin UI for v1.
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
