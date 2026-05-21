import XCTest
@testable import Xomper

/// Mirrors `AdminStoreTests` but covers the Preseason AI Review flow
/// added in F2. Reuses the same `MockAdminAPIClient` fixture from
/// `AdminStoreTests.swift` — the mock supports both flows so a single
/// store can be exercised end-to-end.
@MainActor
final class AdminStorePreseasonTests: XCTestCase {

    // MARK: - Fixtures

    private func makePreseasonReport(
        dryRun: Bool = true,
        createdAt: Date = Date()
    ) -> AIReport {
        AIReport(
            id: "L1|REPORT#preseason#2026-PRESEASON",
            leagueId: "L1",
            reportType: .preseason,
            period: "2026-PRESEASON",
            bodyMarkdown: "## Team A\nLast year: 11-3. This year: contender.",
            metadata: ["dry_run": dryRun ? "true" : "false"],
            createdAt: createdAt,
            model: "claude-haiku-4-5",
            promptVersion: "f2-preseason-2026-05-21"
        )
    }

    private func makeTriggerResponse(
        dryRun: Bool = true,
        deliveryCount: Int = 1
    ) -> AIReviewTriggerResponse {
        // Decode from JSON so we exercise the same path the network
        // client does. Memberwise init isn't synthesized for these
        // Decodable-only structs.
        let json = """
        {
          "report_id": "L1|REPORT#preseason#2026-PRESEASON",
          "dry_run": \(dryRun),
          "delivery_count": \(deliveryCount),
          "model": "claude-haiku-4-5",
          "token_usage": { "input_tokens": 1234, "output_tokens": 567 }
        }
        """
        return try! JSONDecoder().decode(
            AIReviewTriggerResponse.self,
            from: Data(json.utf8)
        )
    }

    // MARK: - loadPreseasonLatest

    func testLoadPreseasonLatest_populatesFromMockClient() async {
        let report = makePreseasonReport()
        let mock = MockAdminAPIClient(preseasonLatest: report)
        let store = AdminStore(apiClient: mock)

        await store.loadPreseasonLatest()

        XCTAssertEqual(store.preseasonLatest?.id, report.id)
        XCTAssertEqual(mock.fetchLatestCalls, [.preseason])
    }

    func testLoadPreseasonLatest_silentOnFailure() async {
        let mock = MockAdminAPIClient(preseasonFetchError: MockError.boom)
        let store = AdminStore(apiClient: mock)

        await store.loadPreseasonLatest()

        XCTAssertNil(store.preseasonLatest)
    }

    // MARK: - triggerPreseason success

    func testTriggerPreseason_returnsResultAndUpdatesState() async throws {
        let report = makePreseasonReport()
        let response = makeTriggerResponse(dryRun: true, deliveryCount: 1)
        let mock = MockAdminAPIClient(
            preseasonLatest: report,
            preseasonTriggerResponse: response
        )
        let store = AdminStore(apiClient: mock)

        let result = try await store.triggerPreseason(dryRun: true, force: false)

        XCTAssertEqual(result.reportId, "L1|REPORT#preseason#2026-PRESEASON")
        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.deliveryCount, 1)
        XCTAssertEqual(store.preseasonResult?.reportId, response.reportId)
        XCTAssertNil(store.preseasonError)
        XCTAssertFalse(store.isTriggeringPreseason)
        // Should refresh latest after success.
        XCTAssertEqual(mock.fetchLatestCalls, [.preseason])
        XCTAssertEqual(mock.preseasonTriggerCalls.count, 1)
        XCTAssertEqual(mock.preseasonTriggerCalls.first?.dryRun, true)
        XCTAssertEqual(mock.preseasonTriggerCalls.first?.force, false)
    }

    func testTriggerPreseason_broadcastPath() async throws {
        let response = makeTriggerResponse(dryRun: false, deliveryCount: 12)
        let mock = MockAdminAPIClient(preseasonTriggerResponse: response)
        let store = AdminStore(apiClient: mock)

        let result = try await store.triggerPreseason(dryRun: false, force: true)

        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.deliveryCount, 12)
        XCTAssertEqual(mock.preseasonTriggerCalls.first?.dryRun, false)
        XCTAssertEqual(mock.preseasonTriggerCalls.first?.force, true)
    }

    // MARK: - triggerPreseason error

    func testTriggerPreseason_surfacesError() async {
        let mock = MockAdminAPIClient(preseasonTriggerError: MockError.boom)
        let store = AdminStore(apiClient: mock)

        do {
            _ = try await store.triggerPreseason(dryRun: true, force: false)
            XCTFail("Expected throw")
        } catch {
            // Expected.
        }

        XCTAssertNotNil(store.preseasonError)
        XCTAssertNil(store.preseasonResult)
        XCTAssertFalse(store.isTriggeringPreseason)
    }

    // MARK: - Wire-format guard: preseason raw value

    func testAIReportType_decodesPreseason() throws {
        let json = "\"preseason\""
        let decoded = try JSONDecoder().decode(
            AIReportType.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded, .preseason)
        XCTAssertEqual(decoded.rawValue, "preseason")
    }
}
