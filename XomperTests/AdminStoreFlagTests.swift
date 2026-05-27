import XCTest
@testable import Xomper

/// F3 — verifies `AdminStore.setReportFlag` round-trips through the
/// API client with the right arguments, re-loads the affected
/// `*Latest` so the UI reflects the new metadata, and surfaces
/// errors via `throws`. Also covers `AIReviewStore.setReportFlag`
/// mutation-in-place behavior on the archive cache.
@MainActor
final class AdminStoreFlagTests: XCTestCase {

    // MARK: - Fixtures

    private func makeWeeklyReport(metadata: [String: String] = [:]) -> AIReport {
        AIReport(
            id: "L1|REPORT#weekly#2026W04",
            leagueId: "L1",
            reportType: .weekly,
            period: "2026W04",
            bodyMarkdown: "## Week 4",
            metadata: metadata,
            createdAt: Date(timeIntervalSince1970: 0),
            model: "claude-haiku-4-5",
            promptVersion: "f0-2026-05-21"
        )
    }

    private func makeFlagResponse(
        flag: ReportFlag,
        value: Bool,
        metadata: [String: String]
    ) -> ReportFlagResponse {
        // Render via JSON so we exercise the same Decodable path the
        // real network client takes.
        let metaJson = metadata.map { "\"\($0.key)\": \"\($0.value)\"" }
            .joined(separator: ", ")
        let json = """
        {
          "Success": true,
          "league_id": "L1",
          "report_type": "weekly",
          "period": "2026W04",
          "flag": "\(flag.rawValue)",
          "value": \(value),
          "metadata": { \(metaJson) }
        }
        """
        return try! JSONDecoder().decode(
            ReportFlagResponse.self,
            from: Data(json.utf8)
        )
    }

    // MARK: - AdminStore.setReportFlag

    /// Happy path: setReportFlag calls the API client with the right
    /// args, returns the updated metadata, and re-loads the affected
    /// `*Latest` so trigger card + preview view reflect the new state.
    func test_adminSetReportFlag_callsAPIWithRightArgs() async throws {
        let report = makeWeeklyReport()
        let response = makeFlagResponse(
            flag: .doNotBroadcast,
            value: true,
            metadata: ["do_not_broadcast": "true"]
        )
        let updatedLatest = makeWeeklyReport(metadata: ["do_not_broadcast": "true"])
        let mock = MockAdminAPIClient(weeklyLatest: updatedLatest)
        mock.setReportFlagResponse = response
        let store = AdminStore(apiClient: mock)

        let returnedMetadata = try await store.setReportFlag(
            report: report,
            flag: .doNotBroadcast,
            value: true
        )

        // API client called exactly once with the report's (leagueId,
        // reportType, period) + the flag + value the caller passed in.
        XCTAssertEqual(mock.setReportFlagCalls.count, 1)
        let call = mock.setReportFlagCalls[0]
        XCTAssertEqual(call.leagueId, "L1")
        XCTAssertEqual(call.reportType, .weekly)
        XCTAssertEqual(call.period, "2026W04")
        XCTAssertEqual(call.flag, .doNotBroadcast)
        XCTAssertTrue(call.value)

        // Returns the backend's updated metadata so the caller can
        // apply it locally (mirrors the wire response).
        XCTAssertEqual(returnedMetadata["do_not_broadcast"], "true")

        // Re-fetched weekly latest so the trigger card / preview view
        // pick up the new DNB state without manual refresh.
        XCTAssertEqual(mock.fetchLatestCalls, [.weekly])
        XCTAssertEqual(store.weeklyLatest?.doNotBroadcast, true)
    }

    /// Error path: API throws, AdminStore re-throws, and `*Latest`
    /// is NOT re-fetched (no point — nothing changed server-side).
    func test_adminSetReportFlag_errorRethrowsAndSkipsReload() async {
        let report = makeWeeklyReport()
        let mock = MockAdminAPIClient()
        mock.setReportFlagError = MockError.boom
        let store = AdminStore(apiClient: mock)

        do {
            _ = try await store.setReportFlag(
                report: report,
                flag: .doNotBroadcast,
                value: true
            )
            XCTFail("Expected throw")
        } catch {
            // Expected.
        }

        XCTAssertEqual(mock.setReportFlagCalls.count, 1)
        XCTAssertTrue(mock.fetchLatestCalls.isEmpty, "Should not re-fetch latest on error")
    }

    /// Latest accessor: returns the right cached report for each type
    /// (or nil for mock). Used by the preview view to read the
    /// current DNB state without switching on the type at the call
    /// site.
    func test_adminStore_latestAccessorReturnsByType() async {
        let weekly = makeWeeklyReport(metadata: ["do_not_broadcast": "true"])
        let mock = MockAdminAPIClient(weeklyLatest: weekly)
        let store = AdminStore(apiClient: mock)

        await store.loadWeeklyLatest()

        XCTAssertEqual(store.latest(for: .weekly)?.id, weekly.id)
        XCTAssertNil(store.latest(for: .postDraft))
        XCTAssertNil(store.latest(for: .preseason))
        XCTAssertNil(store.latest(for: .mock))
    }

    // MARK: - AIReviewStore.setReportFlag (archive mutation)

    /// `setReportFlag` mutates the matching `archive` entry in place
    /// using the backend's authoritative metadata map — no need for
    /// a follow-up `/ai-reports/list` round-trip.
    func test_aiReviewStore_setReportFlagMutatesArchiveInPlace() async throws {
        let original = AIReport(
            id: "L1|REPORT#weekly#2026W04",
            leagueId: "L1",
            reportType: .weekly,
            period: "2026W04",
            bodyMarkdown: "## Week 4",
            metadata: [:],
            createdAt: Date(timeIntervalSince1970: 0),
            model: "claude-haiku-4-5",
            promptVersion: "f0-2026-05-21"
        )
        let other = AIReport(
            id: "L1|REPORT#weekly#2026W03",
            leagueId: "L1",
            reportType: .weekly,
            period: "2026W03",
            bodyMarkdown: "## Week 3",
            metadata: [:],
            createdAt: Date(timeIntervalSince1970: 0),
            model: "claude-haiku-4-5",
            promptVersion: "f0-2026-05-21"
        )
        let mock = MockXomperAPIClient(listPages: [(rows: [original, other], cursor: nil)])
        let json = """
        {
          "Success": true,
          "league_id": "L1",
          "report_type": "weekly",
          "period": "2026W04",
          "flag": "is_redacted",
          "value": true,
          "metadata": { "is_redacted": "true" }
        }
        """
        mock.setReportFlagResponse = try JSONDecoder().decode(
            ReportFlagResponse.self,
            from: Data(json.utf8)
        )
        let store = AIReviewStore(apiClient: mock)
        await store.loadArchive()
        XCTAssertEqual(store.archive.count, 2)

        try await store.setReportFlag(
            report: original,
            flag: .isRedacted,
            value: true
        )

        // Target row is now flagged; sibling is untouched.
        XCTAssertEqual(store.archive.count, 2)
        let mutated = store.archive.first(where: { $0.id == original.id })
        XCTAssertNotNil(mutated)
        XCTAssertTrue(mutated?.isRedacted == true)
        let sibling = store.archive.first(where: { $0.id == other.id })
        XCTAssertEqual(sibling?.isRedacted, false)
    }

    /// API failure leaves the archive untouched — instant-feedback
    /// mutation is gated on a successful round-trip.
    func test_aiReviewStore_setReportFlagErrorLeavesArchiveUntouched() async {
        let original = AIReport(
            id: "L1|REPORT#weekly#2026W04",
            leagueId: "L1",
            reportType: .weekly,
            period: "2026W04",
            bodyMarkdown: "## Week 4",
            metadata: [:],
            createdAt: Date(timeIntervalSince1970: 0),
            model: "claude-haiku-4-5",
            promptVersion: "f0-2026-05-21"
        )
        let mock = MockXomperAPIClient(listPages: [(rows: [original], cursor: nil)])
        mock.setReportFlagError = MockXomperAPIClient.Unsupported.method
        let store = AIReviewStore(apiClient: mock)
        await store.loadArchive()

        do {
            _ = try await store.setReportFlag(
                report: original,
                flag: .isRedacted,
                value: true
            )
            XCTFail("Expected throw")
        } catch {
            // Expected.
        }

        // Row unchanged — no mutation on failure.
        XCTAssertEqual(store.archive.first?.isRedacted, false)
    }
}
