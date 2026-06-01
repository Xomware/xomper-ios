import XCTest
@testable import Xomper

/// admin-cron-settings — drives `CronSettingsStore` through its loader
/// + toggle paths using a mock `XomperAPIClientProtocol`. Covers:
/// happy-path load, tableMissing empty state, optimistic toggle +
/// revert-on-error, server reconciliation, duplicate-toggle dedup, and
/// the `anyTestModeActive` derived flag that drives the banner.
@MainActor
final class CronSettingsStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSetting(
        cronKey: String = "notif_weekly_recap",
        enabled: Bool = true,
        testMode: Bool = false,
        description: String? = "Weekly recap"
    ) -> CronSetting {
        CronSetting(
            cronKey: cronKey,
            enabled: enabled,
            testMode: testMode,
            description: description,
            updatedAt: nil
        )
    }

    // MARK: - load

    func test_load_populatesFromMock() async {
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(
                count: 2,
                rows: [
                    makeSetting(cronKey: "notif_weekly_recap"),
                    makeSetting(cronKey: "notif_lineup_not_set", enabled: false),
                ],
                tableMissing: false
            )
        )
        let store = CronSettingsStore(apiClient: mock)

        await store.load()

        XCTAssertEqual(store.settings.count, 2)
        XCTAssertFalse(store.tableMissing)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isLoading)
    }

    func test_load_tableMissingFlagsEmptyState() async {
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(
                count: 0,
                rows: [],
                tableMissing: true
            )
        )
        let store = CronSettingsStore(apiClient: mock)

        await store.load()

        XCTAssertTrue(store.settings.isEmpty)
        XCTAssertTrue(store.tableMissing)
    }

    func test_load_surfacesError() async {
        let mock = MockCronSettingsAPIClient(listError: CronMockError.boom)
        let store = CronSettingsStore(apiClient: mock)

        await store.load()

        XCTAssertTrue(store.settings.isEmpty)
        XCTAssertNotNil(store.error)
    }

    // MARK: - toggleEnabled

    func test_toggleEnabled_optimisticUpdateAndServerReconciliation() async {
        let initial = makeSetting(enabled: true, testMode: false)
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(count: 1, rows: [initial], tableMissing: false),
            updateResponse: CronSettingUpdateResponse(
                cronKey: initial.cronKey,
                enabled: false,
                testMode: false
            )
        )
        let store = CronSettingsStore(apiClient: mock)
        await store.load()

        await store.toggleEnabled(cronKey: initial.cronKey, enabled: false)

        XCTAssertEqual(mock.updateCalls.count, 1)
        XCTAssertEqual(mock.updateCalls.first?.enabled, false)
        XCTAssertNil(mock.updateCalls.first?.testMode, "testMode unset when toggling enabled only")
        XCTAssertEqual(store.settings.first?.enabled, false)
        XCTAssertNil(store.lastError)
    }

    func test_toggleEnabled_revertsOnError() async {
        let initial = makeSetting(enabled: true)
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(count: 1, rows: [initial], tableMissing: false),
            updateError: CronMockError.boom
        )
        let store = CronSettingsStore(apiClient: mock)
        await store.load()

        await store.toggleEnabled(cronKey: initial.cronKey, enabled: false)

        XCTAssertEqual(store.settings.first?.enabled, true, "Reverted to pre-toggle state on error.")
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.pendingKeys.isEmpty, "Pending key cleared even on failure.")
    }

    // MARK: - toggleTestMode

    func test_toggleTestMode_optimisticUpdate() async {
        let initial = makeSetting(enabled: true, testMode: false)
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(count: 1, rows: [initial], tableMissing: false),
            updateResponse: CronSettingUpdateResponse(
                cronKey: initial.cronKey,
                enabled: true,
                testMode: true
            )
        )
        let store = CronSettingsStore(apiClient: mock)
        await store.load()

        await store.toggleTestMode(cronKey: initial.cronKey, testMode: true)

        XCTAssertEqual(mock.updateCalls.count, 1)
        XCTAssertEqual(mock.updateCalls.first?.testMode, true)
        XCTAssertNil(mock.updateCalls.first?.enabled, "enabled unset when toggling testMode only")
        XCTAssertEqual(store.settings.first?.testMode, true)
    }

    func test_toggleTestMode_revertsOnError() async {
        let initial = makeSetting(enabled: true, testMode: false)
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(count: 1, rows: [initial], tableMissing: false),
            updateError: CronMockError.boom
        )
        let store = CronSettingsStore(apiClient: mock)
        await store.load()

        await store.toggleTestMode(cronKey: initial.cronKey, testMode: true)

        XCTAssertEqual(store.settings.first?.testMode, false, "Reverted to pre-toggle state on error.")
        XCTAssertNotNil(store.lastError)
    }

    // MARK: - dedup

    func test_toggleEnabled_dedupesWhilePending() async {
        // Use an explicitly slow update so the second tap arrives while
        // the first is in flight. We can't await across two toggles in a
        // single task, so spawn them and wait on the group.
        let initial = makeSetting(enabled: true)
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(count: 1, rows: [initial], tableMissing: false),
            updateResponse: CronSettingUpdateResponse(
                cronKey: initial.cronKey,
                enabled: false,
                testMode: false
            ),
            updateDelayNanos: 50_000_000 // 50ms
        )
        let store = CronSettingsStore(apiClient: mock)
        await store.load()

        async let first: Void = store.toggleEnabled(cronKey: initial.cronKey, enabled: false)
        // Yield so the first toggle inserts into pendingKeys before the second runs.
        await Task.yield()
        async let second: Void = store.toggleEnabled(cronKey: initial.cronKey, enabled: false)
        _ = await (first, second)

        XCTAssertEqual(mock.updateCalls.count, 1, "Duplicate-while-pending toggle should be dropped.")
    }

    // MARK: - anyTestModeActive

    func test_anyTestModeActive_trueWhenAnyRowHasTestMode() async {
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(
                count: 2,
                rows: [
                    makeSetting(cronKey: "a", testMode: false),
                    makeSetting(cronKey: "b", testMode: true),
                ],
                tableMissing: false
            )
        )
        let store = CronSettingsStore(apiClient: mock)
        await store.load()

        XCTAssertTrue(store.anyTestModeActive)
    }

    func test_anyTestModeActive_falseWhenAllOff() async {
        let mock = MockCronSettingsAPIClient(
            listResponse: CronSettingsListResponse(
                count: 2,
                rows: [
                    makeSetting(cronKey: "a", testMode: false),
                    makeSetting(cronKey: "b", testMode: false),
                ],
                tableMissing: false
            )
        )
        let store = CronSettingsStore(apiClient: mock)
        await store.load()

        XCTAssertFalse(store.anyTestModeActive)
    }
}

// MARK: - Mock API client

final class MockCronSettingsAPIClient: XomperAPIClientProtocol, @unchecked Sendable {
    var listResponse: CronSettingsListResponse?
    var listError: Error?
    var updateResponse: CronSettingUpdateResponse?
    var updateError: Error?
    var updateDelayNanos: UInt64 = 0

    private(set) var updateCalls: [(cronKey: String, enabled: Bool?, testMode: Bool?)] = []

    init(
        listResponse: CronSettingsListResponse? = nil,
        listError: Error? = nil,
        updateResponse: CronSettingUpdateResponse? = nil,
        updateError: Error? = nil,
        updateDelayNanos: UInt64 = 0
    ) {
        self.listResponse = listResponse
        self.listError = listError
        self.updateResponse = updateResponse
        self.updateError = updateError
        self.updateDelayNanos = updateDelayNanos
    }

    func fetchCronSettings() async throws -> CronSettingsListResponse {
        if let err = listError { throw err }
        return listResponse ?? CronSettingsListResponse(count: 0, rows: [], tableMissing: false)
    }

    func updateCronSetting(
        cronKey: String,
        enabled: Bool?,
        testMode: Bool?
    ) async throws -> CronSettingUpdateResponse {
        updateCalls.append((cronKey, enabled, testMode))
        if updateDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: updateDelayNanos)
        }
        if let err = updateError { throw err }
        guard let response = updateResponse else {
            throw CronMockError.notConfigured
        }
        return response
    }

    // MARK: - Unused protocol surface

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws { throw CronMockError.unsupported }
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw CronMockError.unsupported }
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw CronMockError.unsupported }
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws { throw CronMockError.unsupported }
    func registerDevice(userId: String, deviceToken: String) async throws { throw CronMockError.unsupported }
    func unregisterDevice(userId: String, deviceToken: String) async throws { throw CronMockError.unsupported }
    func adminListNotifications(sleeperUserId: String, daysBack: Int, kind: String?, status: String?, limit: Int) async throws -> AdminNotificationsResponse { throw CronMockError.unsupported }
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse { throw CronMockError.unsupported }
    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient] { throw CronMockError.unsupported }
    func sendTestEmail(recipientSleeperUserId: String, reportId: String) async throws -> TestEmailResponse { throw CronMockError.unsupported }
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? { nil }
    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse { AIReportsListResponse(rows: [], nextCursor: nil) }
    func fetchAIReportByPeriod(type: AIReportType, period: String) async throws -> AIReport? { nil }
    func fetchMockDrafts() async throws -> [AIReport] { [] }
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw CronMockError.unsupported }
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw CronMockError.unsupported }
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw CronMockError.unsupported }
    func setReportFlag(leagueId: String, reportType: AIReportType, period: String, flag: ReportFlag, value: Bool) async throws -> ReportFlagResponse { throw CronMockError.unsupported }
    func fetchWhitelistedUsers() async throws -> [WhitelistedUser] { throw CronMockError.unsupported }
    func updateWhitelistedUser(userId: String, fields: [String: AdminFieldValue]) async throws -> UserUpdateResponse { throw CronMockError.unsupported }
    func fetchAdminWhitelistedLeagues() async throws -> [WhitelistedLeague] { throw CronMockError.unsupported }
    func updateWhitelistedLeague(leagueId: String, fields: [String: AdminFieldValue]) async throws -> LeagueUpdateResponse { throw CronMockError.unsupported }
    func fetchAuditEntries(limit: Int, cursor: String?) async throws -> AuditListResponse { throw CronMockError.unsupported }
    func fetchLogEvents(logGroup: LogGroup, level: LogLevel?, search: String?, limit: Int, cursor: String?) async throws -> LogsQueryResponse { throw CronMockError.unsupported }
}

enum CronMockError: Error, LocalizedError {
    case boom
    case unsupported
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .boom: "boom"
        case .unsupported: "mock method not supported"
        case .notConfigured: "mock response not configured"
        }
    }
}
