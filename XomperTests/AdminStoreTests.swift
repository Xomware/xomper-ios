import XCTest
@testable import Xomper

@MainActor
final class AdminStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func makePostDraftReport(
        dryRun: Bool = true,
        createdAt: Date = Date()
    ) -> AIReport {
        AIReport(
            id: "L1|REPORT#postDraft#2026",
            leagueId: "L1",
            reportType: .postDraft,
            period: "2026",
            bodyMarkdown: "## Team A\nGood draft.",
            metadata: ["dry_run": dryRun ? "true" : "false"],
            createdAt: createdAt,
            model: "claude-haiku-4-5",
            promptVersion: "f1-2026-05-21"
        )
    }

    private func makeTriggerResponse(
        dryRun: Bool = true,
        deliveryCount: Int = 1,
        report: AIReport? = nil
    ) -> AIReviewTriggerResponse {
        // Decode from JSON so we exercise the same path the network
        // client does. Memberwise init isn't synthesized for these
        // Decodable-only structs.
        let reportJson: String
        if let report {
            // Tiny inline rendering — we only need report_id to satisfy
            // the trigger response. Decoding the full AIReport is
            // covered by AIReviewStoreTests.
            reportJson = ", \"report\": { \"pk\": \"LEAGUE#L1\", \"sk\": \"REPORT#postDraft#2026\", \"league_id\": \"L1\", \"report_type\": \"postDraft\", \"period\": \"2026\", \"body_markdown\": \"\(report.bodyMarkdown)\", \"created_at\": \"2026-05-21T00:00:00Z\" }"
        } else {
            reportJson = ""
        }
        let json = """
        {
          "report_id": "L1|REPORT#postDraft#2026",
          "dry_run": \(dryRun),
          "delivery_count": \(deliveryCount),
          "model": "claude-haiku-4-5",
          "token_usage": { "input_tokens": 1234, "output_tokens": 567 }
          \(reportJson)
        }
        """
        return try! JSONDecoder().decode(
            AIReviewTriggerResponse.self,
            from: Data(json.utf8)
        )
    }

    // MARK: - loadPostDraftLatest

    func testLoadPostDraftLatest_populatesFromMockClient() async {
        let report = makePostDraftReport()
        let mock = MockAdminAPIClient(latest: report)
        let store = AdminStore(apiClient: mock)

        await store.loadPostDraftLatest()

        XCTAssertEqual(store.postDraftLatest?.id, report.id)
        XCTAssertEqual(mock.fetchLatestCalls, [.postDraft])
    }

    func testLoadPostDraftLatest_silentOnFailure() async {
        let mock = MockAdminAPIClient(fetchLatestError: MockError.boom)
        let store = AdminStore(apiClient: mock)

        await store.loadPostDraftLatest()

        XCTAssertNil(store.postDraftLatest)
    }

    // MARK: - triggerPostDraft success

    func testTriggerPostDraft_returnsResultAndUpdatesState() async throws {
        let report = makePostDraftReport()
        let response = makeTriggerResponse(dryRun: true, deliveryCount: 1)
        let mock = MockAdminAPIClient(
            latest: report,
            triggerResponse: response
        )
        let store = AdminStore(apiClient: mock)

        let result = try await store.triggerPostDraft(dryRun: true, force: false)

        XCTAssertEqual(result.reportId, "L1|REPORT#postDraft#2026")
        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.deliveryCount, 1)
        XCTAssertEqual(store.postDraftResult?.reportId, response.reportId)
        XCTAssertNil(store.postDraftError)
        XCTAssertFalse(store.isTriggeringPostDraft)
        // Should refresh latest after success.
        XCTAssertEqual(mock.fetchLatestCalls, [.postDraft])
        XCTAssertEqual(mock.triggerCalls.count, 1)
        XCTAssertEqual(mock.triggerCalls.first?.dryRun, true)
        XCTAssertEqual(mock.triggerCalls.first?.force, false)
    }

    func testTriggerPostDraft_broadcastPath() async throws {
        let response = makeTriggerResponse(dryRun: false, deliveryCount: 12)
        let mock = MockAdminAPIClient(triggerResponse: response)
        let store = AdminStore(apiClient: mock)

        let result = try await store.triggerPostDraft(dryRun: false, force: true)

        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.deliveryCount, 12)
        XCTAssertEqual(mock.triggerCalls.first?.dryRun, false)
        XCTAssertEqual(mock.triggerCalls.first?.force, true)
    }

    // MARK: - triggerPostDraft error

    func testTriggerPostDraft_surfacesError() async {
        let mock = MockAdminAPIClient(triggerError: MockError.boom)
        let store = AdminStore(apiClient: mock)

        do {
            _ = try await store.triggerPostDraft(dryRun: true, force: false)
            XCTFail("Expected throw")
        } catch {
            // Expected.
        }

        XCTAssertNotNil(store.postDraftError)
        XCTAssertNil(store.postDraftResult)
        XCTAssertFalse(store.isTriggeringPostDraft)
    }

    // MARK: - Wire-format guard: postDraft raw value

    func testAIReportType_decodesCamelCasePostDraft() throws {
        let json = "\"postDraft\""
        let decoded = try JSONDecoder().decode(
            AIReportType.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded, .postDraft)
        XCTAssertEqual(decoded.rawValue, "postDraft")
    }
}

// MARK: - Mock API Client

/// Sendable mock for AdminStore tests. Implements the full protocol
/// surface so the type checks compile; non-admin methods throw to
/// catch accidental calls.
final class MockAdminAPIClient: XomperAPIClientProtocol, @unchecked Sendable {
    var latest: AIReport?
    var fetchLatestError: Error?
    var triggerResponse: AIReviewTriggerResponse?
    var triggerError: Error?

    // Optional per-type overrides so a single mock can drive both
    // post-draft and preseason flows. When nil, falls back to the
    // shared `latest` / `triggerResponse` / `*Error` fields above so
    // existing post-draft tests keep working without modification.
    var preseasonLatest: AIReport?
    var preseasonFetchError: Error?
    var preseasonTriggerResponse: AIReviewTriggerResponse?
    var preseasonTriggerError: Error?

    // Weekly overrides (F3). Same pattern — when nil, falls back to
    // shared fields so single-type fixtures stay simple.
    var weeklyLatest: AIReport?
    var weeklyFetchError: Error?
    var weeklyTriggerResponse: AIReviewTriggerResponse?
    var weeklyTriggerError: Error?

    private(set) var fetchLatestCalls: [AIReportType] = []
    private(set) var triggerCalls: [(dryRun: Bool, force: Bool)] = []
    private(set) var preseasonTriggerCalls: [(dryRun: Bool, force: Bool)] = []
    /// Captures each weekly trigger invocation. `week` is recorded
    /// verbatim so tests can assert both the override + omitted paths.
    private(set) var weeklyTriggerCalls: [(week: Int?, dryRun: Bool, force: Bool)] = []

    init(
        latest: AIReport? = nil,
        fetchLatestError: Error? = nil,
        triggerResponse: AIReviewTriggerResponse? = nil,
        triggerError: Error? = nil,
        preseasonLatest: AIReport? = nil,
        preseasonFetchError: Error? = nil,
        preseasonTriggerResponse: AIReviewTriggerResponse? = nil,
        preseasonTriggerError: Error? = nil,
        weeklyLatest: AIReport? = nil,
        weeklyFetchError: Error? = nil,
        weeklyTriggerResponse: AIReviewTriggerResponse? = nil,
        weeklyTriggerError: Error? = nil
    ) {
        self.latest = latest
        self.fetchLatestError = fetchLatestError
        self.triggerResponse = triggerResponse
        self.triggerError = triggerError
        self.preseasonLatest = preseasonLatest
        self.preseasonFetchError = preseasonFetchError
        self.preseasonTriggerResponse = preseasonTriggerResponse
        self.preseasonTriggerError = preseasonTriggerError
        self.weeklyLatest = weeklyLatest
        self.weeklyFetchError = weeklyFetchError
        self.weeklyTriggerResponse = weeklyTriggerResponse
        self.weeklyTriggerError = weeklyTriggerError
    }

    // MARK: AI Review

    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? {
        fetchLatestCalls.append(type)
        switch type {
        case .preseason:
            if let err = preseasonFetchError { throw err }
            // Fall back to `latest` if no preseason-specific row was
            // staged — keeps single-type fixtures simple.
            return preseasonLatest ?? latest
        case .weekly:
            if let err = weeklyFetchError { throw err }
            return weeklyLatest ?? latest
        default:
            if let err = fetchLatestError { throw err }
            return latest
        }
    }

    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse {
        AIReportsListResponse(rows: [], nextCursor: nil)
    }

    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse {
        triggerCalls.append((dryRun, force))
        if let err = triggerError { throw err }
        guard let response = triggerResponse else { throw MockError.notConfigured }
        return response
    }

    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse {
        preseasonTriggerCalls.append((dryRun, force))
        if let err = preseasonTriggerError { throw err }
        guard let response = preseasonTriggerResponse else { throw MockError.notConfigured }
        return response
    }

    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse {
        weeklyTriggerCalls.append((week, dryRun, force))
        if let err = weeklyTriggerError { throw err }
        guard let response = weeklyTriggerResponse else { throw MockError.notConfigured }
        return response
    }

    // MARK: Unused protocol surface

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws { throw MockError.unsupported }
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw MockError.unsupported }
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw MockError.unsupported }
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws { throw MockError.unsupported }
    func registerDevice(userId: String, deviceToken: String) async throws { throw MockError.unsupported }
    func unregisterDevice(userId: String, deviceToken: String) async throws { throw MockError.unsupported }
    func adminListNotifications(sleeperUserId: String, daysBack: Int, kind: String?, status: String?, limit: Int) async throws -> AdminNotificationsResponse { throw MockError.unsupported }
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse { throw MockError.unsupported }
}

enum MockError: Error, LocalizedError {
    case boom
    case unsupported
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .boom: "boom"
        case .unsupported: "mock method not supported"
        case .notConfigured: "mock not configured"
        }
    }
}
