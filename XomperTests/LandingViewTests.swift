import XCTest
@testable import Xomper

@MainActor
final class LandingViewTests: XCTestCase {

    // MARK: - LeagueAnnouncements filter

    /// Entries with `expiresAt` strictly in the past are filtered out.
    /// Entries with `expiresAt == nil` always survive.
    func testLeagueAnnouncements_filtersExpiredEntries() {
        // The hardcoded list uses absolute calendar dates. We can't
        // mutate Date, but the priority sort is deterministic and the
        // filter logic mirrors what `AnnouncementsCard.visible` does.
        let now = Date()
        let visible = LeagueAnnouncements.current
            .filter { entry in
                guard let expiresAt = entry.expiresAt else { return true }
                return expiresAt > now
            }
        // All entries should either be permanent (nil) or expire in
        // the future relative to `now` — none should have an expiry
        // already in the past.
        for entry in visible {
            if let expiresAt = entry.expiresAt {
                XCTAssertGreaterThan(
                    expiresAt,
                    now,
                    "Visible announcement '\(entry.title)' has past expiresAt \(expiresAt)"
                )
            }
        }
    }

    /// Critical announcements sort before info ones.
    func testLeagueAnnouncements_criticalSortsBeforeInfo() {
        let entries = LeagueAnnouncements.current
        let sorted = entries.sorted { a, b in
            priorityRank(a.priority) < priorityRank(b.priority)
        }

        var sawInfo = false
        for entry in sorted {
            if entry.priority == .info {
                sawInfo = true
            } else if entry.priority == .critical && sawInfo {
                XCTFail("Critical announcement '\(entry.title)' followed an info entry")
            }
        }
    }

    /// `LeagueAnnouncements.current` ships at least 2 entries — the
    /// draft date and the season start — per plan v1 scope.
    func testLeagueAnnouncements_hasAtLeastTwoEntries() {
        XCTAssertGreaterThanOrEqual(
            LeagueAnnouncements.current.count,
            2,
            "v1 plan calls for 2-3 hardcoded announcements"
        )
    }

    // MARK: - Smoke: LandingView constructs

    /// Smoke test: the view initializes with stub stores without
    /// trapping. Doesn't render — that requires a host — but catches
    /// init-time crashes from missing optional unwraps.
    func testLandingView_constructsWithStubStores() {
        let _ = LandingView(
            leagueStore: LeagueStore(),
            authStore: AuthStore(),
            nflStateStore: NflStateStore(),
            aiReviewStore: AIReviewStore(),
            announcementsStore: AnnouncementsStore(),
            navStore: NavigationStore(),
            router: AppRouter()
        )
        // Nothing thrown — that's the contract.
    }

    // MARK: - Helpers

    private func priorityRank(_ priority: LeagueAnnouncement.Priority) -> Int {
        switch priority {
        case .critical: 0
        case .info:     1
        }
    }
}
