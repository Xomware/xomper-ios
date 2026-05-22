import XCTest
@testable import Xomper

/// Coverage for the side effects the Archive's `PastDraftPickerView` row tap
/// performs:
///
///   1. `SeasonStore.select(year)` — sets the shared `selectedSeason` if it's
///      in the `availableSeasons` set.
///   2. `NavigationStore.select(.draftHistory, router:)` — flips the
///      top-level destination and closes the drawer.
///
/// The view itself isn't constructed; we drive the same store calls the
/// button action wires up so the contract is locked even if the view
/// rebody-changes.
@MainActor
final class ArchiveNavigationTests: XCTestCase {

    /// Selecting a past year should land both stores in the expected
    /// post-tap state: `selectedSeason` updated and `currentDestination`
    /// flipped to `.draftHistory`.
    func testPastDraftRowTap_setsSeasonAndDestination() {
        // Arrange — seed the season store as it would be in production:
        // current season 2026, plus past years 2024 + 2025 available.
        let seasonStore = SeasonStore()
        seasonStore.refreshAvailable(
            matchupSeasons: ["2024", "2025"],
            draftSeasons: ["2024", "2025", "2026"],
            chainSeasons: ["2024", "2025", "2026"],
            currentSeason: "2026"
        )
        // Default selection after bootstrap is the current season.
        XCTAssertEqual(seasonStore.selectedSeason, "2026")

        let navStore = NavigationStore()
        XCTAssertEqual(navStore.currentDestination, .landing)

        // Act — same side effects PastDraftPickerView fires on row tap.
        seasonStore.select("2024")
        navStore.select(.draftHistory, router: nil)

        // Assert — both stores now reflect the past-draft selection.
        XCTAssertEqual(seasonStore.selectedSeason, "2024")
        XCTAssertEqual(navStore.currentDestination, .draftHistory)
        XCTAssertFalse(navStore.isDrawerOpen)
    }

    /// `SeasonStore.select(_:)` is defensive — selecting a year that isn't
    /// in `availableSeasons` should be a no-op so a stale tap can't strand
    /// the user on a non-existent season chip.
    func testPastDraftRowTap_unknownYearIsNoop() {
        let seasonStore = SeasonStore()
        seasonStore.refreshAvailable(
            matchupSeasons: ["2024"],
            draftSeasons: ["2024"],
            chainSeasons: ["2024"],
            currentSeason: "2024"
        )
        XCTAssertEqual(seasonStore.selectedSeason, "2024")

        seasonStore.select("1999")

        XCTAssertEqual(
            seasonStore.selectedSeason,
            "2024",
            "selecting an unavailable season should not mutate the store"
        )
    }
}
