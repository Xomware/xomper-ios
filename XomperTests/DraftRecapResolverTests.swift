import XCTest
@testable import Xomper

/// Tests for the postDraft recap filter that lives on `DraftRecapView`
/// (Season Refocus F3 — Draft tab restructure). The filter is lifted
/// to a static helper (`DraftRecapView.matchingReport(in:year:)`) so
/// tests can drive it without view materialization.
@MainActor
final class DraftRecapResolverTests: XCTestCase {

    // MARK: - Fixtures

    private func makeReport(
        id: String,
        type: AIReportType,
        period: String,
        createdAt: Date = Date()
    ) -> AIReport {
        AIReport(
            id: id,
            leagueId: "L1",
            reportType: type,
            period: period,
            bodyMarkdown: "## Recap\nBody.",
            metadata: [:],
            createdAt: createdAt,
            model: "claude-haiku-4-5",
            promptVersion: "f0-2026-05-21"
        )
    }

    // MARK: - Test 1: matches a single postDraft report for the year

    func testMatchingReport_singlePostDraft_returnsIt() {
        let report = makeReport(
            id: "L1|REPORT#postDraft#2026",
            type: .postDraft,
            period: "2026"
        )

        let match = DraftRecapView.matchingReport(in: [report], year: "2026")

        XCTAssertNotNil(match)
        XCTAssertEqual(match?.id, report.id)
    }

    // MARK: - Test 2: picks the right year when multiple postDraft reports exist

    func testMatchingReport_multipleYears_filtersToSelected() {
        let r2024 = makeReport(
            id: "L1|REPORT#postDraft#2024",
            type: .postDraft,
            period: "2024"
        )
        let r2025 = makeReport(
            id: "L1|REPORT#postDraft#2025",
            type: .postDraft,
            period: "2025"
        )
        let r2026 = makeReport(
            id: "L1|REPORT#postDraft#2026",
            type: .postDraft,
            period: "2026"
        )
        // Archive is newest-first per the store contract.
        let archive = [r2026, r2025, r2024]

        let match = DraftRecapView.matchingReport(in: archive, year: "2025")

        XCTAssertEqual(match?.id, r2025.id)
    }

    // MARK: - Test 3: returns nil when no postDraft reports exist

    func testMatchingReport_onlyWeeklyReports_returnsNil() {
        let weekly = makeReport(
            id: "L1|REPORT#weekly#2026W04",
            type: .weekly,
            period: "2026W04"
        )

        let match = DraftRecapView.matchingReport(in: [weekly], year: "2026")

        XCTAssertNil(match)
    }

    // MARK: - Test 4: returns the first (newest) when duplicates exist

    func testMatchingReport_duplicatePostDraftSameYear_returnsFirst() {
        let newer = makeReport(
            id: "L1|REPORT#postDraft#2026-v2",
            type: .postDraft,
            period: "2026",
            createdAt: Date()
        )
        let older = makeReport(
            id: "L1|REPORT#postDraft#2026-v1",
            type: .postDraft,
            period: "2026",
            createdAt: Date(timeIntervalSinceNow: -86400)
        )
        // Archive is newest-first sorted upstream.
        let archive = [newer, older]

        let match = DraftRecapView.matchingReport(in: archive, year: "2026")

        XCTAssertEqual(match?.id, newer.id)
    }

    // MARK: - Test 5: substring match works for period strings like "2026-POSTDRAFT"

    func testMatchingReport_periodWithSuffix_stillMatches() {
        let report = makeReport(
            id: "L1|REPORT#postDraft#2026-POSTDRAFT",
            type: .postDraft,
            period: "2026-POSTDRAFT"
        )

        let match = DraftRecapView.matchingReport(in: [report], year: "2026")

        XCTAssertEqual(match?.id, report.id)
    }

    // MARK: - Test 6: empty year returns nil (defensive)

    func testMatchingReport_emptyYear_returnsNil() {
        let report = makeReport(
            id: "L1|REPORT#postDraft#2026",
            type: .postDraft,
            period: "2026"
        )

        let match = DraftRecapView.matchingReport(in: [report], year: "")

        XCTAssertNil(match)
    }

    // MARK: - Test 7: empty archive returns nil

    func testMatchingReport_emptyArchive_returnsNil() {
        let match = DraftRecapView.matchingReport(in: [], year: "2026")
        XCTAssertNil(match)
    }

    // MARK: - Test 8: type=postDraft fetch surfaces past-year recaps
    // that the global archive's first-page limit would have buried

    /// Simulates the production fix: the view now reads from
    /// `aiReviewStore.postDraftArchive`, populated by
    /// `loadPostDraftArchive()` which calls
    /// `fetchAIReportsList(type: .postDraft, limit: 20)`. As long as
    /// the postDraft archive contains the 2024 row, the resolver finds
    /// it — regardless of how many weekly / mock rows sit "ahead" of it
    /// in the global archive.
    func testPostDraftArchive_resolvesOldYearEvenWithLargeOtherCorpus() {
        // 39-row corpus (36 weekly + 2 postDraft + 3 mock) where the
        // 2024 postDraft is buried after 30 weekly rows by createdAt.
        // The dedicated postDraft fetch trims to just the two postDraft
        // rows, so the resolver lands on 2024 in O(2).
        let postDraft2024 = makeReport(
            id: "L1|REPORT#postDraft#2024",
            type: .postDraft,
            period: "2024",
            createdAt: Date(timeIntervalSinceNow: -86_400 * 600)
        )
        let postDraft2025 = makeReport(
            id: "L1|REPORT#postDraft#2025",
            type: .postDraft,
            period: "2025",
            createdAt: Date(timeIntervalSinceNow: -86_400 * 300)
        )
        // What `postDraftArchive` ends up holding (newest-first).
        let postDraftArchive = [postDraft2025, postDraft2024]

        let match2024 = DraftRecapView.matchingReport(
            in: postDraftArchive,
            year: "2024"
        )
        XCTAssertEqual(match2024?.id, postDraft2024.id)

        let match2025 = DraftRecapView.matchingReport(
            in: postDraftArchive,
            year: "2025"
        )
        XCTAssertEqual(match2025?.id, postDraft2025.id)
    }
}
