import XCTest
@testable import Xomper

/// Tests for the per-season sub-tab list logic on the Draft surface
/// (Season Refocus F3). The helper lives in `DraftSubTabSelection` so
/// tests can drive it without materializing the view.
final class DraftSubTabSelectionTests: XCTestCase {

    // MARK: - Current season → Live / Mocks / Recap

    func testAvailableSubTabs_currentSeason_returnsLiveMocksRecap() {
        let tabs = DraftSubTabSelection.availableSubTabs(isCurrentSeason: true)
        XCTAssertEqual(tabs, [.live, .mocks, .recap])
    }

    // MARK: - Past season → Picks / Recap

    func testAvailableSubTabs_pastSeason_returnsPicksRecap() {
        let tabs = DraftSubTabSelection.availableSubTabs(isCurrentSeason: false)
        XCTAssertEqual(tabs, [.picks, .recap])
    }

    // MARK: - Default sub-tab

    func testDefaultSubTab_currentSeason_isLive() {
        XCTAssertEqual(
            DraftSubTabSelection.defaultSubTab(isCurrentSeason: true),
            .live
        )
    }

    func testDefaultSubTab_pastSeason_isPicks() {
        XCTAssertEqual(
            DraftSubTabSelection.defaultSubTab(isCurrentSeason: false),
            .picks
        )
    }

    // MARK: - Default sub-tab is always in the available list

    func testDefaultSubTab_isInAvailableList_currentSeason() {
        let tabs = DraftSubTabSelection.availableSubTabs(isCurrentSeason: true)
        let def = DraftSubTabSelection.defaultSubTab(isCurrentSeason: true)
        XCTAssertTrue(tabs.contains(def))
    }

    func testDefaultSubTab_isInAvailableList_pastSeason() {
        let tabs = DraftSubTabSelection.availableSubTabs(isCurrentSeason: false)
        let def = DraftSubTabSelection.defaultSubTab(isCurrentSeason: false)
        XCTAssertTrue(tabs.contains(def))
    }

    // MARK: - Sub-tab labels (sanity)

    func testSubTabLabels_areHumanReadable() {
        XCTAssertEqual(DraftSubTab.live.label, "Live")
        XCTAssertEqual(DraftSubTab.mocks.label, "Mocks")
        XCTAssertEqual(DraftSubTab.recap.label, "Recap")
        XCTAssertEqual(DraftSubTab.picks.label, "Picks")
    }
}
