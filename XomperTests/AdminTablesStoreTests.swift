import XCTest
@testable import Xomper

/// F4 — drives `AdminTablesStore` through its loader + writer paths
/// using a mock `XomperAPIClientProtocol`. Covers users + leagues +
/// audit (including the `table_missing` empty-state signal and
/// cursor pagination).
@MainActor
final class AdminTablesStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func makeUser(
        id: String = "row-uuid",
        sleeperId: String? = "12345",
        email: String = "alice@example.com",
        name: String? = "Alice",
        isAdmin: Bool = false,
        isActive: Bool = true
    ) -> WhitelistedUser {
        WhitelistedUser(
            id: id,
            email: email,
            sleeperUsername: name,
            sleeperUserId: sleeperId,
            displayName: name,
            role: nil,
            isActive: isActive,
            isAdmin: isAdmin
        )
    }

    private func makeLeague(
        leagueId: String = "L1",
        name: String = "CLT Dynasty",
        isActive: Bool = true,
        isDynasty: Bool = true,
        hasTaxi: Bool = false
    ) -> WhitelistedLeague {
        WhitelistedLeague(
            id: "row-\(leagueId)",
            leagueId: leagueId,
            leagueName: name,
            season: "2026",
            isActive: isActive,
            isDynasty: isDynasty,
            hasTaxi: hasTaxi,
            divisions: 2,
            size: 12
        )
    }

    private func makeAudit(
        id: String = UUID().uuidString,
        action: String = "users.update",
        target: String? = "12345"
    ) -> AuditEntry {
        AuditEntry(
            id: id,
            createdAt: Date(),
            actorUserId: "admin-1",
            action: action,
            targetTable: "whitelisted_users",
            targetId: target,
            before: .object(["is_admin": .bool(false)]),
            after: .object(["is_admin": .bool(true)]),
            metadata: nil
        )
    }

    // MARK: - loadUsers

    func test_loadUsers_populatesFromMock() async {
        let mock = MockAdminTablesAPIClient(
            users: [makeUser(sleeperId: "1"), makeUser(sleeperId: "2", name: "Bob")]
        )
        let store = AdminTablesStore(apiClient: mock)

        await store.loadUsers()

        XCTAssertEqual(store.users.count, 2)
        XCTAssertNil(store.usersError)
        XCTAssertFalse(store.isLoadingUsers)
    }

    func test_loadUsers_surfacesError() async {
        let mock = MockAdminTablesAPIClient(usersError: AdminTablesMockError.boom)
        let store = AdminTablesStore(apiClient: mock)

        await store.loadUsers()

        XCTAssertTrue(store.users.isEmpty)
        XCTAssertNotNil(store.usersError)
    }

    // MARK: - loadLeagues

    func test_loadLeagues_populatesFromMock() async {
        let mock = MockAdminTablesAPIClient(leagues: [makeLeague()])
        let store = AdminTablesStore(apiClient: mock)

        await store.loadLeagues()

        XCTAssertEqual(store.leagues.count, 1)
        XCTAssertNil(store.leaguesError)
    }

    func test_loadLeagues_surfacesError() async {
        let mock = MockAdminTablesAPIClient(leaguesError: AdminTablesMockError.boom)
        let store = AdminTablesStore(apiClient: mock)

        await store.loadLeagues()

        XCTAssertTrue(store.leagues.isEmpty)
        XCTAssertNotNil(store.leaguesError)
    }

    // MARK: - loadAudit

    func test_loadAudit_resetPopulates() async {
        let mock = MockAdminTablesAPIClient(
            auditResponse: AuditListResponse(
                success: true,
                count: 2,
                rows: [makeAudit(id: "a"), makeAudit(id: "b")],
                nextCursor: "cursor-1",
                tableMissing: false
            )
        )
        let store = AdminTablesStore(apiClient: mock)

        await store.loadAudit(reset: true)

        XCTAssertEqual(store.auditEntries.count, 2)
        XCTAssertEqual(store.auditNextCursor, "cursor-1")
        XCTAssertTrue(store.hasMoreAudit)
        XCTAssertFalse(store.auditTableMissing)
    }

    func test_loadAudit_tableMissingFlagsEmptyState() async {
        let mock = MockAdminTablesAPIClient(
            auditResponse: AuditListResponse(
                success: true,
                count: 0,
                rows: [],
                nextCursor: nil,
                tableMissing: true
            )
        )
        let store = AdminTablesStore(apiClient: mock)

        await store.loadAudit(reset: true)

        XCTAssertTrue(store.auditEntries.isEmpty)
        XCTAssertTrue(store.auditTableMissing)
        XCTAssertFalse(store.hasMoreAudit)
    }

    func test_loadMoreAudit_appendsAndAdvancesCursor() async {
        let mock = MockAdminTablesAPIClient(
            auditResponse: AuditListResponse(
                success: true,
                count: 1,
                rows: [makeAudit(id: "first")],
                nextCursor: "cursor-1",
                tableMissing: false
            )
        )
        let store = AdminTablesStore(apiClient: mock)
        await store.loadAudit(reset: true)
        XCTAssertEqual(store.auditEntries.count, 1)

        // Second page swaps in a different response.
        mock.auditResponse = AuditListResponse(
            success: true,
            count: 1,
            rows: [makeAudit(id: "second")],
            nextCursor: nil,
            tableMissing: false
        )

        await store.loadMoreAudit()

        XCTAssertEqual(store.auditEntries.count, 2)
        XCTAssertEqual(store.auditEntries.last?.id, "second")
        XCTAssertNil(store.auditNextCursor)
        XCTAssertFalse(store.hasMoreAudit)
    }

    func test_loadMoreAudit_noopWhenNoMore() async {
        let mock = MockAdminTablesAPIClient(
            auditResponse: AuditListResponse(
                success: true,
                count: 1,
                rows: [makeAudit(id: "only")],
                nextCursor: nil,
                tableMissing: false
            )
        )
        let store = AdminTablesStore(apiClient: mock)
        await store.loadAudit(reset: true)
        let callsBefore = mock.fetchAuditCallCount

        await store.loadMoreAudit()

        XCTAssertEqual(mock.fetchAuditCallCount, callsBefore, "No extra API call when cursor is nil.")
        XCTAssertEqual(store.auditEntries.count, 1)
    }

    // MARK: - updateUser

    func test_updateUser_happyPathMutatesInPlace() async {
        let initial = makeUser(sleeperId: "12345", isAdmin: false)
        let mock = MockAdminTablesAPIClient(
            users: [initial],
            userUpdateResponse: UserUpdateResponse(
                success: true,
                userId: "12345",
                before: .object(["is_admin": .bool(false)]),
                after: .object(["is_admin": .bool(true)])
            )
        )
        let store = AdminTablesStore(apiClient: mock)
        await store.loadUsers()

        await store.updateUser(
            userId: "12345",
            fields: ["is_admin": .bool(true)]
        )

        XCTAssertEqual(mock.userUpdateCalls.count, 1)
        XCTAssertEqual(mock.userUpdateCalls.first?.userId, "12345")
        XCTAssertEqual(store.users.first?.isAdmin, true)
        XCTAssertEqual(store.lastSaveSuccess, "12345")
        XCTAssertNil(store.lastSaveError)
    }

    func test_updateUser_errorLeavesStateUntouched() async {
        let initial = makeUser(sleeperId: "12345", isAdmin: false)
        let mock = MockAdminTablesAPIClient(
            users: [initial],
            userUpdateError: AdminTablesMockError.boom
        )
        let store = AdminTablesStore(apiClient: mock)
        await store.loadUsers()

        await store.updateUser(
            userId: "12345",
            fields: ["is_admin": .bool(true)]
        )

        XCTAssertEqual(store.users.first?.isAdmin, false, "No in-place mutation on error.")
        XCTAssertNotNil(store.lastSaveError)
        XCTAssertNil(store.lastSaveSuccess)
    }

    func test_updateUser_noopWhenFieldsEmpty() async {
        let mock = MockAdminTablesAPIClient(
            users: [makeUser(sleeperId: "12345")]
        )
        let store = AdminTablesStore(apiClient: mock)
        await store.loadUsers()

        await store.updateUser(userId: "12345", fields: [:])

        XCTAssertEqual(mock.userUpdateCalls.count, 0, "Empty diff doesn't hit the API.")
        XCTAssertNil(store.lastSaveSuccess)
        XCTAssertNil(store.lastSaveError)
    }

    // MARK: - updateLeague

    func test_updateLeague_happyPathMutatesInPlace() async {
        let initial = makeLeague(leagueId: "L1", isDynasty: false)
        let mock = MockAdminTablesAPIClient(
            leagues: [initial],
            leagueUpdateResponse: LeagueUpdateResponse(
                success: true,
                leagueId: "L1",
                before: .object(["is_dynasty": .bool(false)]),
                after: .object(["is_dynasty": .bool(true)])
            )
        )
        let store = AdminTablesStore(apiClient: mock)
        await store.loadLeagues()

        await store.updateLeague(
            leagueId: "L1",
            fields: ["is_dynasty": .bool(true)]
        )

        XCTAssertEqual(mock.leagueUpdateCalls.count, 1)
        XCTAssertEqual(store.leagues.first?.isDynasty, true)
        XCTAssertEqual(store.lastSaveSuccess, "L1")
    }

    // MARK: - clearLastSaveResult

    func test_clearLastSaveResult_resetsBothSides() async {
        let initial = makeUser(sleeperId: "12345")
        let mock = MockAdminTablesAPIClient(
            users: [initial],
            userUpdateResponse: UserUpdateResponse(
                success: true,
                userId: "12345",
                before: .object([:]),
                after: .object([:])
            )
        )
        let store = AdminTablesStore(apiClient: mock)
        await store.loadUsers()
        await store.updateUser(
            userId: "12345",
            fields: ["display_name": .string("Renamed")]
        )
        XCTAssertNotNil(store.lastSaveSuccess)

        store.clearLastSaveResult()

        XCTAssertNil(store.lastSaveSuccess)
        XCTAssertNil(store.lastSaveError)
    }
}

// MARK: - Mock API client

final class MockAdminTablesAPIClient: XomperAPIClientProtocol, @unchecked Sendable {
    var users: [WhitelistedUser]
    var usersError: Error?
    var leagues: [WhitelistedLeague]
    var leaguesError: Error?
    var auditResponse: AuditListResponse?
    var auditError: Error?
    var userUpdateResponse: UserUpdateResponse?
    var userUpdateError: Error?
    var leagueUpdateResponse: LeagueUpdateResponse?
    var leagueUpdateError: Error?

    private(set) var userUpdateCalls: [(userId: String, fields: [String: AdminFieldValue])] = []
    private(set) var leagueUpdateCalls: [(leagueId: String, fields: [String: AdminFieldValue])] = []
    private(set) var fetchAuditCallCount = 0

    init(
        users: [WhitelistedUser] = [],
        usersError: Error? = nil,
        leagues: [WhitelistedLeague] = [],
        leaguesError: Error? = nil,
        auditResponse: AuditListResponse? = nil,
        auditError: Error? = nil,
        userUpdateResponse: UserUpdateResponse? = nil,
        userUpdateError: Error? = nil,
        leagueUpdateResponse: LeagueUpdateResponse? = nil,
        leagueUpdateError: Error? = nil
    ) {
        self.users = users
        self.usersError = usersError
        self.leagues = leagues
        self.leaguesError = leaguesError
        self.auditResponse = auditResponse
        self.auditError = auditError
        self.userUpdateResponse = userUpdateResponse
        self.userUpdateError = userUpdateError
        self.leagueUpdateResponse = leagueUpdateResponse
        self.leagueUpdateError = leagueUpdateError
    }

    func fetchWhitelistedUsers() async throws -> [WhitelistedUser] {
        if let err = usersError { throw err }
        return users
    }

    func updateWhitelistedUser(
        userId: String,
        fields: [String: AdminFieldValue]
    ) async throws -> UserUpdateResponse {
        userUpdateCalls.append((userId, fields))
        if let err = userUpdateError { throw err }
        guard let response = userUpdateResponse else {
            throw AdminTablesMockError.notConfigured
        }
        return response
    }

    func fetchAdminWhitelistedLeagues() async throws -> [WhitelistedLeague] {
        if let err = leaguesError { throw err }
        return leagues
    }

    func updateWhitelistedLeague(
        leagueId: String,
        fields: [String: AdminFieldValue]
    ) async throws -> LeagueUpdateResponse {
        leagueUpdateCalls.append((leagueId, fields))
        if let err = leagueUpdateError { throw err }
        guard let response = leagueUpdateResponse else {
            throw AdminTablesMockError.notConfigured
        }
        return response
    }

    func fetchAuditEntries(
        limit: Int,
        cursor: String?
    ) async throws -> AuditListResponse {
        fetchAuditCallCount += 1
        if let err = auditError { throw err }
        return auditResponse ?? AuditListResponse(
            success: true,
            count: 0,
            rows: [],
            nextCursor: nil,
            tableMissing: false
        )
    }

    // MARK: Unused protocol surface

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws { throw AdminTablesMockError.unsupported }
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw AdminTablesMockError.unsupported }
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw AdminTablesMockError.unsupported }
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws { throw AdminTablesMockError.unsupported }
    func registerDevice(userId: String, deviceToken: String) async throws { throw AdminTablesMockError.unsupported }
    func unregisterDevice(userId: String, deviceToken: String) async throws { throw AdminTablesMockError.unsupported }
    func adminListNotifications(sleeperUserId: String, daysBack: Int, kind: String?, status: String?, limit: Int) async throws -> AdminNotificationsResponse { throw AdminTablesMockError.unsupported }
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse { throw AdminTablesMockError.unsupported }
    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient] { throw AdminTablesMockError.unsupported }
    func sendTestEmail(recipientSleeperUserId: String, reportId: String) async throws -> TestEmailResponse { throw AdminTablesMockError.unsupported }
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? { nil }
    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse { AIReportsListResponse(rows: [], nextCursor: nil) }
    func fetchAIReportByPeriod(type: AIReportType, period: String) async throws -> AIReport? { nil }
    func fetchMockDrafts() async throws -> [AIReport] { [] }
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw AdminTablesMockError.unsupported }
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw AdminTablesMockError.unsupported }
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw AdminTablesMockError.unsupported }
    func setReportFlag(leagueId: String, reportType: AIReportType, period: String, flag: ReportFlag, value: Bool) async throws -> ReportFlagResponse { throw AdminTablesMockError.unsupported }
    func fetchLogEvents(logGroup: LogGroup, level: LogLevel?, search: String?, limit: Int, cursor: String?) async throws -> LogsQueryResponse { throw AdminTablesMockError.unsupported }
    func fetchCronSettings() async throws -> CronSettingsListResponse { throw AdminTablesMockError.unsupported }
    func updateCronSetting(cronKey: String, enabled: Bool?, testMode: Bool?) async throws -> CronSettingUpdateResponse { throw AdminTablesMockError.unsupported }
}

enum AdminTablesMockError: Error, LocalizedError {
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
