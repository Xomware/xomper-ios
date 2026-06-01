import XCTest
@testable import Xomper

/// F5 — drives `LogsStore` through its loader + pagination + rate
/// limit paths using a mock `XomperAPIClientProtocol`.
@MainActor
final class LogsStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func makeEvent(
        id: String = UUID().uuidString,
        level: LogLevel? = .info,
        message: String = "msg"
    ) -> LogEvent {
        LogEvent(
            id: id,
            timestamp: Date(),
            level: level,
            message: message
        )
    }

    private func makeResponse(
        events: [LogEvent] = [],
        nextToken: String? = nil
    ) -> LogsQueryResponse {
        LogsQueryResponse(
            success: true,
            logGroup: "ai-review-weekly",
            events: events,
            nextToken: nextToken
        )
    }

    // MARK: - loadEvents happy path

    func test_loadEvents_populatesEventsAndStampsLastFetch() async {
        let mock = MockLogsAPIClient(
            response: makeResponse(events: [makeEvent(id: "a"), makeEvent(id: "b")])
        )
        let store = LogsStore(apiClient: mock)

        await store.loadEvents()

        XCTAssertEqual(store.events.count, 2)
        XCTAssertNotNil(store.lastFetchAt)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.error)
        XCTAssertEqual(mock.fetchCallCount, 1)
    }

    func test_loadEvents_passesFiltersToAPI() async {
        let mock = MockLogsAPIClient(response: makeResponse())
        let store = LogsStore(apiClient: mock)

        store.selectedLogGroup = .emailTest
        store.levelFilter = .error
        store.searchText = "draft"

        await store.loadEvents()

        let call = mock.lastFetchCall
        XCTAssertEqual(call?.logGroup, .emailTest)
        XCTAssertEqual(call?.level, .error)
        XCTAssertEqual(call?.search, "draft")
        XCTAssertNil(call?.cursor, "First-page load should not pass a cursor.")
    }

    func test_loadEvents_emptySearchPassesNilToAPI() async {
        let mock = MockLogsAPIClient(response: makeResponse())
        let store = LogsStore(apiClient: mock)

        store.searchText = ""

        await store.loadEvents()

        XCTAssertNil(mock.lastFetchCall?.search, "Empty search should map to nil, not empty string.")
    }

    func test_loadEvents_surfacesError() async {
        let mock = MockLogsAPIClient(error: LogsMockError.boom)
        let store = LogsStore(apiClient: mock)

        await store.loadEvents()

        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.events.isEmpty)
    }

    // MARK: - Rate limit

    func test_loadEvents_withinFiveSecondsIsThrottled() async {
        let mock = MockLogsAPIClient(response: makeResponse(events: [makeEvent()]))
        let store = LogsStore(apiClient: mock)

        await store.loadEvents()
        XCTAssertEqual(mock.fetchCallCount, 1)

        // Second call immediately after — should be blocked.
        await store.loadEvents()

        XCTAssertEqual(mock.fetchCallCount, 1, "Second load within 5s window must not call the API.")
        XCTAssertTrue(store.throttled, "Throttle flag should flip on for the banner.")
    }

    func test_loadMore_doesNotRespectRateLimit() async {
        let firstResponse = makeResponse(
            events: [makeEvent(id: "a"), makeEvent(id: "b")],
            nextToken: "cursor-1"
        )
        let secondResponse = makeResponse(
            events: [makeEvent(id: "c"), makeEvent(id: "d")],
            nextToken: nil
        )
        let mock = MockLogsAPIClient(responses: [firstResponse, secondResponse])
        let store = LogsStore(apiClient: mock)

        await store.loadEvents()
        XCTAssertEqual(store.events.count, 2)

        // Pagination immediately after — should bypass throttle.
        await store.loadMore()

        XCTAssertEqual(mock.fetchCallCount, 2, "loadMore must not be rate-limited.")
        XCTAssertEqual(store.events.count, 4, "loadMore should append, not replace.")
        XCTAssertNil(store.nextToken)
        XCTAssertFalse(store.throttled, "Pagination should not trip the throttle banner.")
    }

    func test_loadMore_noTokenIsNoOp() async {
        let mock = MockLogsAPIClient(response: makeResponse(events: [makeEvent()], nextToken: nil))
        let store = LogsStore(apiClient: mock)
        await store.loadEvents()
        XCTAssertEqual(mock.fetchCallCount, 1)

        await store.loadMore()

        XCTAssertEqual(mock.fetchCallCount, 1, "loadMore without a cursor should not call the API.")
    }

    func test_loadMore_dedupesEventsByID() async {
        let firstResponse = makeResponse(
            events: [makeEvent(id: "a"), makeEvent(id: "b")],
            nextToken: "cursor-1"
        )
        // Backend (or a cursor cycle) returns event "b" again on the
        // next page. The store must filter the dup to avoid SwiftUI
        // ForEach asserting on duplicate ids.
        let secondResponse = makeResponse(
            events: [makeEvent(id: "b"), makeEvent(id: "c")],
            nextToken: nil
        )
        let mock = MockLogsAPIClient(responses: [firstResponse, secondResponse])
        let store = LogsStore(apiClient: mock)

        await store.loadEvents()
        await store.loadMore()

        XCTAssertEqual(store.events.map(\.id), ["a", "b", "c"])
    }

    // MARK: - Filter mutations

    func test_setLogGroup_resetsFetchTimestampAndReloads() async {
        let mock = MockLogsAPIClient(response: makeResponse(events: [makeEvent()]))
        let store = LogsStore(apiClient: mock)

        await store.loadEvents()
        XCTAssertEqual(mock.fetchCallCount, 1)

        // Without the rate-limit reset this would no-op.
        await store.setLogGroup(.usersUpdate)

        XCTAssertEqual(mock.fetchCallCount, 2)
        XCTAssertEqual(store.selectedLogGroup, .usersUpdate)
        XCTAssertEqual(mock.lastFetchCall?.logGroup, .usersUpdate)
    }

    func test_setLevel_resetsFetchTimestampAndReloads() async {
        let mock = MockLogsAPIClient(response: makeResponse(events: [makeEvent()]))
        let store = LogsStore(apiClient: mock)

        await store.loadEvents()
        await store.setLevel(.error)

        XCTAssertEqual(mock.fetchCallCount, 2)
        XCTAssertEqual(store.levelFilter, .error)
        XCTAssertEqual(mock.lastFetchCall?.level, .error)
    }

    func test_resetFilters_clearsSearchAndLevel() {
        let store = LogsStore(apiClient: MockLogsAPIClient(response: makeResponse()))
        store.searchText = "boom"
        store.levelFilter = .warn
        store.selectedLogGroup = .emailTest

        store.resetFilters()

        XCTAssertEqual(store.searchText, "")
        XCTAssertNil(store.levelFilter)
        XCTAssertEqual(store.selectedLogGroup, .aiReviewWeekly)
    }
}

// MARK: - Mock API client

final class MockLogsAPIClient: XomperAPIClientProtocol, @unchecked Sendable {
    /// Configured responses — popped in order. Falls back to
    /// `defaultResponse` once drained. Captures arguments for assertion.
    private var queuedResponses: [LogsQueryResponse]
    private let defaultResponse: LogsQueryResponse
    private let error: Error?

    private(set) var fetchCallCount = 0
    private(set) var lastFetchCall: (
        logGroup: LogGroup,
        level: LogLevel?,
        search: String?,
        limit: Int,
        cursor: String?
    )?

    init(response: LogsQueryResponse, error: Error? = nil) {
        self.queuedResponses = []
        self.defaultResponse = response
        self.error = error
    }

    init(responses: [LogsQueryResponse]) {
        self.queuedResponses = responses
        self.defaultResponse = LogsQueryResponse(
            success: true,
            logGroup: "ai-review-weekly",
            events: [],
            nextToken: nil
        )
        self.error = nil
    }

    init(error: Error) {
        self.queuedResponses = []
        self.defaultResponse = LogsQueryResponse(
            success: false,
            logGroup: "",
            events: [],
            nextToken: nil
        )
        self.error = error
    }

    func fetchLogEvents(
        logGroup: LogGroup,
        level: LogLevel?,
        search: String?,
        limit: Int,
        cursor: String?
    ) async throws -> LogsQueryResponse {
        fetchCallCount += 1
        lastFetchCall = (logGroup, level, search, limit, cursor)
        if let error { throw error }
        if !queuedResponses.isEmpty {
            return queuedResponses.removeFirst()
        }
        return defaultResponse
    }

    // MARK: - Unused protocol surface

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws { throw LogsMockError.unsupported }
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw LogsMockError.unsupported }
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw LogsMockError.unsupported }
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws { throw LogsMockError.unsupported }
    func registerDevice(userId: String, deviceToken: String) async throws { throw LogsMockError.unsupported }
    func unregisterDevice(userId: String, deviceToken: String) async throws { throw LogsMockError.unsupported }
    func adminListNotifications(sleeperUserId: String, daysBack: Int, kind: String?, status: String?, limit: Int) async throws -> AdminNotificationsResponse { throw LogsMockError.unsupported }
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse { throw LogsMockError.unsupported }
    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient] { throw LogsMockError.unsupported }
    func sendTestEmail(recipientSleeperUserId: String, reportId: String) async throws -> TestEmailResponse { throw LogsMockError.unsupported }
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? { nil }
    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse { AIReportsListResponse(rows: [], nextCursor: nil) }
    func fetchAIReportByPeriod(type: AIReportType, period: String) async throws -> AIReport? { nil }
    func fetchMockDrafts() async throws -> [AIReport] { [] }
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw LogsMockError.unsupported }
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw LogsMockError.unsupported }
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw LogsMockError.unsupported }
    func setReportFlag(leagueId: String, reportType: AIReportType, period: String, flag: ReportFlag, value: Bool) async throws -> ReportFlagResponse { throw LogsMockError.unsupported }
    func fetchWhitelistedUsers() async throws -> [WhitelistedUser] { throw LogsMockError.unsupported }
    func updateWhitelistedUser(userId: String, fields: [String: AdminFieldValue]) async throws -> UserUpdateResponse { throw LogsMockError.unsupported }
    func fetchAdminWhitelistedLeagues() async throws -> [WhitelistedLeague] { throw LogsMockError.unsupported }
    func updateWhitelistedLeague(leagueId: String, fields: [String: AdminFieldValue]) async throws -> LeagueUpdateResponse { throw LogsMockError.unsupported }
    func fetchAuditEntries(limit: Int, cursor: String?) async throws -> AuditListResponse { throw LogsMockError.unsupported }
    func fetchCronSettings() async throws -> CronSettingsListResponse { throw LogsMockError.unsupported }
    func updateCronSetting(cronKey: String, enabled: Bool?, testMode: Bool?) async throws -> CronSettingUpdateResponse { throw LogsMockError.unsupported }
}

enum LogsMockError: Error, LocalizedError {
    case boom
    case unsupported

    var errorDescription: String? {
        switch self {
        case .boom: "boom"
        case .unsupported: "mock method not supported"
        }
    }
}
