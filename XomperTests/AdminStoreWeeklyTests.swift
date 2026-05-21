import XCTest
@testable import Xomper

/// Covers the Weekly AI Review flow added in F3. Mirrors
/// `AdminStorePreseasonTests` for the store-level behaviors and adds a
/// wire-format guard on `WeeklyTriggerRequest`: when `week == nil` the
/// JSON key must be omitted entirely (so the backend's
/// `nfl_state.week - 1` default kicks in) rather than emitted as
/// `"week": null`.
///
/// Reuses `MockAdminAPIClient` from `AdminStoreTests.swift`.
@MainActor
final class AdminStoreWeeklyTests: XCTestCase {

    // MARK: - Fixtures

    private func makeWeeklyReport(
        dryRun: Bool = true,
        period: String = "2026W04",
        createdAt: Date = Date()
    ) -> AIReport {
        AIReport(
            id: "L1|REPORT#weekly#\(period)",
            leagueId: "L1",
            reportType: .weekly,
            period: period,
            bodyMarkdown: "# Week 4 Roast\n\nThe headline...",
            metadata: ["dry_run": dryRun ? "true" : "false"],
            createdAt: createdAt,
            model: "claude-haiku-4-5",
            promptVersion: "f3-weekly-2026-05-21"
        )
    }

    private func makeTriggerResponse(
        dryRun: Bool = true,
        deliveryCount: Int = 1,
        period: String = "2026W04"
    ) -> AIReviewTriggerResponse {
        // Decode from JSON to exercise the same path the network
        // client does. Memberwise init isn't synthesized for these
        // Decodable-only structs.
        let json = """
        {
          "report_id": "L1|REPORT#weekly#\(period)",
          "dry_run": \(dryRun),
          "delivery_count": \(deliveryCount),
          "model": "claude-haiku-4-5",
          "token_usage": { "input_tokens": 4321, "output_tokens": 2890 }
        }
        """
        return try! JSONDecoder().decode(
            AIReviewTriggerResponse.self,
            from: Data(json.utf8)
        )
    }

    // MARK: - loadWeeklyLatest

    func testLoadWeeklyLatest_populatesFromMockClient() async {
        let report = makeWeeklyReport()
        let mock = MockAdminAPIClient(weeklyLatest: report)
        let store = AdminStore(apiClient: mock)

        await store.loadWeeklyLatest()

        XCTAssertEqual(store.weeklyLatest?.id, report.id)
        XCTAssertEqual(mock.fetchLatestCalls, [.weekly])
    }

    func testLoadWeeklyLatest_silentOnFailure() async {
        let mock = MockAdminAPIClient(weeklyFetchError: MockError.boom)
        let store = AdminStore(apiClient: mock)

        await store.loadWeeklyLatest()

        XCTAssertNil(store.weeklyLatest)
    }

    // MARK: - triggerWeekly (defaults — no override)

    func testTriggerWeekly_dryRunWithNoOverride_omitsWeek() async throws {
        let response = makeTriggerResponse(dryRun: true, deliveryCount: 1)
        let mock = MockAdminAPIClient(weeklyTriggerResponse: response)
        let store = AdminStore(apiClient: mock)

        let result = try await store.triggerWeekly(
            week: nil,
            dryRun: true,
            force: false
        )

        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.deliveryCount, 1)
        XCTAssertEqual(store.weeklyResult?.reportId, response.reportId)
        XCTAssertNil(store.weeklyError)
        XCTAssertFalse(store.isTriggeringWeekly)
        XCTAssertEqual(mock.weeklyTriggerCalls.count, 1)
        XCTAssertNil(mock.weeklyTriggerCalls.first?.week)
        XCTAssertEqual(mock.weeklyTriggerCalls.first?.dryRun, true)
        XCTAssertEqual(mock.weeklyTriggerCalls.first?.force, false)
        // Should refresh latest after success.
        XCTAssertEqual(mock.fetchLatestCalls, [.weekly])
    }

    // MARK: - triggerWeekly (explicit week override)

    func testTriggerWeekly_withExplicitWeek_passesOverride() async throws {
        let report = makeWeeklyReport(period: "2026W05")
        let response = makeTriggerResponse(dryRun: true, deliveryCount: 1, period: "2026W05")
        let mock = MockAdminAPIClient(
            weeklyLatest: report,
            weeklyTriggerResponse: response
        )
        let store = AdminStore(apiClient: mock)

        let result = try await store.triggerWeekly(
            week: 5,
            dryRun: true,
            force: false
        )

        XCTAssertEqual(result.reportId, "L1|REPORT#weekly#2026W05")
        XCTAssertEqual(mock.weeklyTriggerCalls.count, 1)
        XCTAssertEqual(mock.weeklyTriggerCalls.first?.week, 5)
    }

    // MARK: - triggerWeekly (broadcast: force + dryRun=false)

    func testTriggerWeekly_broadcastPath() async throws {
        let response = makeTriggerResponse(dryRun: false, deliveryCount: 12)
        let mock = MockAdminAPIClient(weeklyTriggerResponse: response)
        let store = AdminStore(apiClient: mock)

        let result = try await store.triggerWeekly(
            week: 5,
            dryRun: false,
            force: true
        )

        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.deliveryCount, 12)
        XCTAssertEqual(mock.weeklyTriggerCalls.first?.week, 5)
        XCTAssertEqual(mock.weeklyTriggerCalls.first?.dryRun, false)
        XCTAssertEqual(mock.weeklyTriggerCalls.first?.force, true)
    }

    // MARK: - triggerWeekly error

    func testTriggerWeekly_surfacesError() async {
        let mock = MockAdminAPIClient(weeklyTriggerError: MockError.boom)
        let store = AdminStore(apiClient: mock)

        do {
            _ = try await store.triggerWeekly(week: nil, dryRun: true, force: false)
            XCTFail("Expected throw")
        } catch {
            // Expected.
        }

        XCTAssertNotNil(store.weeklyError)
        XCTAssertNil(store.weeklyResult)
        XCTAssertFalse(store.isTriggeringWeekly)
    }

    // MARK: - Wire-format guard: WeeklyTriggerRequest

    /// `week == nil` must omit the JSON key entirely so the backend's
    /// `nfl_state.week - 1` default kicks in. Pydantic configs that
    /// distinguish "missing" from "explicit null" would otherwise read
    /// `"week": null` as an explicit override.
    func testWeeklyTriggerRequest_omitsWeekWhenNil() throws {
        let payload = WeeklyTriggerRequest(week: nil, dryRun: true, force: false)
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertFalse(json.keys.contains("week"),
                       "Expected 'week' key to be omitted when nil, got payload: \(json)")
        XCTAssertEqual(json["dry_run"] as? Bool, true)
        XCTAssertEqual(json["force"] as? Bool, false)
    }

    /// Sanity check: when `week` is non-nil, the JSON key is present
    /// with the expected integer value (and snake-case siblings render
    /// correctly).
    func testWeeklyTriggerRequest_includesWeekWhenSet() throws {
        let payload = WeeklyTriggerRequest(week: 7, dryRun: false, force: true)
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["week"] as? Int, 7)
        XCTAssertEqual(json["dry_run"] as? Bool, false)
        XCTAssertEqual(json["force"] as? Bool, true)
    }

    // MARK: - Wire-format guard: weekly raw value

    func testAIReportType_decodesWeekly() throws {
        let json = "\"weekly\""
        let decoded = try JSONDecoder().decode(
            AIReportType.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded, .weekly)
        XCTAssertEqual(decoded.rawValue, "weekly")
    }
}
