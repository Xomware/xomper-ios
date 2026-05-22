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
}
