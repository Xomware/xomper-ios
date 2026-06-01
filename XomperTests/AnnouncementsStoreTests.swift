import XCTest
@testable import Xomper

/// Drives `AnnouncementsStore` through its public-read + admin CRUD
/// paths using a mock `XomperAPIClientProtocol`. Covers:
/// happy-path load, 5-min cache hit, fallback to
/// `LeagueAnnouncements.current` on error, admin loadAdmin + tableMissing,
/// optimistic create/update/delete, revert on error.
@MainActor
final class AnnouncementsStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func makeAnnouncement(
        id: UUID = UUID(),
        title: String = "Test",
        priority: LeagueAnnouncement.Priority = .info,
        expiresAt: Date? = nil,
        isActive: Bool = true,
        displayOrder: Int = 0
    ) -> LeagueAnnouncement {
        LeagueAnnouncement(
            id: id,
            title: title,
            body: "body",
            priority: priority,
            expiresAt: expiresAt,
            isActive: isActive,
            displayOrder: displayOrder
        )
    }

    // MARK: - Public load

    func test_load_populatesFromMock() async {
        let row = makeAnnouncement(title: "Draft is July 6", priority: .critical)
        let mock = MockAnnouncementsAPIClient(
            publicResponse: AnnouncementsListResponse(success: true, count: 1, rows: [row])
        )
        let store = AnnouncementsStore(apiClient: mock)

        await store.load()

        XCTAssertEqual(store.announcements.count, 1)
        XCTAssertEqual(store.announcements.first?.title, "Draft is July 6")
        XCTAssertNil(store.error)
        XCTAssertNotNil(store.lastLoadedAt)
    }

    func test_load_cacheShortCircuitsWithinFiveMinutes() async {
        let row = makeAnnouncement(title: "Cached")
        let mock = MockAnnouncementsAPIClient(
            publicResponse: AnnouncementsListResponse(success: true, count: 1, rows: [row])
        )
        let store = AnnouncementsStore(apiClient: mock)

        await store.load()
        XCTAssertEqual(mock.publicCallCount, 1)

        // Second call within 5 min should be a no-op.
        await store.load()
        XCTAssertEqual(mock.publicCallCount, 1, "Second load within cache window should be a no-op.")
    }

    func test_load_forceBypassesCache() async {
        let row = makeAnnouncement(title: "Bypass")
        let mock = MockAnnouncementsAPIClient(
            publicResponse: AnnouncementsListResponse(success: true, count: 1, rows: [row])
        )
        let store = AnnouncementsStore(apiClient: mock)

        await store.load()
        await store.load(force: true)

        XCTAssertEqual(mock.publicCallCount, 2)
    }

    func test_load_apiFailureFallsBackToHardcodedList() async {
        let mock = MockAnnouncementsAPIClient(publicError: MockAnnouncementError.boom)
        let store = AnnouncementsStore(apiClient: mock)

        await store.load()

        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.announcements.isEmpty, "Should fall back to LeagueAnnouncements.current.")
        XCTAssertEqual(store.announcements.count, LeagueAnnouncements.current.count)
    }

    func test_load_apiFailurePreservesExistingRowsWhenNonEmpty() async {
        // Successful first load, then a forced failing reload should keep
        // the existing rows on screen (no fallback overwrite).
        let row = makeAnnouncement(title: "Existing")
        let mock = MockAnnouncementsAPIClient(
            publicResponse: AnnouncementsListResponse(success: true, count: 1, rows: [row])
        )
        let store = AnnouncementsStore(apiClient: mock)
        await store.load()
        XCTAssertEqual(store.announcements.first?.title, "Existing")

        mock.publicError = MockAnnouncementError.boom
        await store.load(force: true)

        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.announcements.first?.title, "Existing")
    }

    // MARK: - Admin load

    func test_loadAdmin_populatesIncludesAllRows() async {
        let active = makeAnnouncement(title: "Live", isActive: true)
        let inactive = makeAnnouncement(title: "Archived", isActive: false)
        let mock = MockAnnouncementsAPIClient(
            adminResponse: AdminAnnouncementsListResponse(success: true, count: 2, rows: [active, inactive], tableMissing: false)
        )
        let store = AnnouncementsStore(apiClient: mock)

        await store.loadAdmin()

        XCTAssertEqual(store.adminAnnouncements.count, 2)
        XCTAssertFalse(store.tableMissing)
    }

    func test_loadAdmin_tableMissingFlagsEmptyState() async {
        let mock = MockAnnouncementsAPIClient(
            adminResponse: AdminAnnouncementsListResponse(success: true, count: 0, rows: [], tableMissing: true)
        )
        let store = AnnouncementsStore(apiClient: mock)

        await store.loadAdmin()

        XCTAssertTrue(store.adminAnnouncements.isEmpty)
        XCTAssertTrue(store.tableMissing)
    }

    // MARK: - Admin create

    func test_create_optimisticAndReplacesWithServerRow() async throws {
        let serverRow = makeAnnouncement(title: "Server-resolved")
        let mock = MockAnnouncementsAPIClient(
            mutationResponse: AnnouncementMutationResponse(success: true, row: serverRow)
        )
        let store = AnnouncementsStore(apiClient: mock)

        let result = try await store.create(
            title: "Server-resolved",
            body: "body",
            priority: .info,
            expiresAt: nil,
            isActive: true,
            displayOrder: 0
        )

        XCTAssertEqual(result.id, serverRow.id)
        XCTAssertEqual(store.adminAnnouncements.count, 1)
        XCTAssertEqual(store.adminAnnouncements.first?.id, serverRow.id)
        // Active row should also have appeared on the public list.
        XCTAssertEqual(store.announcements.count, 1)
    }

    func test_create_revertsOnError() async {
        let mock = MockAnnouncementsAPIClient(mutationError: MockAnnouncementError.boom)
        let store = AnnouncementsStore(apiClient: mock)

        do {
            _ = try await store.create(
                title: "Will fail",
                body: "body",
                priority: .info,
                expiresAt: nil,
                isActive: true,
                displayOrder: 0
            )
            XCTFail("create should throw on backend error")
        } catch {
            XCTAssertTrue(store.adminAnnouncements.isEmpty, "Optimistic insert should be reverted.")
            XCTAssertNotNil(store.lastWriteError)
        }
    }

    // MARK: - Admin update

    func test_update_optimisticAndReconcile() async throws {
        let originalId = UUID()
        let original = makeAnnouncement(id: originalId, title: "Old")
        let server = LeagueAnnouncement(
            id: originalId,
            title: "New",
            body: original.body,
            priority: original.priority,
            expiresAt: original.expiresAt,
            isActive: original.isActive,
            displayOrder: original.displayOrder
        )
        let mock = MockAnnouncementsAPIClient(
            adminResponse: AdminAnnouncementsListResponse(success: true, count: 1, rows: [original], tableMissing: false),
            mutationResponse: AnnouncementMutationResponse(success: true, row: server)
        )
        let store = AnnouncementsStore(apiClient: mock)
        await store.loadAdmin()

        _ = try await store.update(id: originalId, fields: ["title": .string("New")])

        XCTAssertEqual(store.adminAnnouncements.first?.title, "New")
    }

    func test_update_revertsOnError() async {
        let originalId = UUID()
        let original = makeAnnouncement(id: originalId, title: "Old")
        let mock = MockAnnouncementsAPIClient(
            adminResponse: AdminAnnouncementsListResponse(success: true, count: 1, rows: [original], tableMissing: false),
            mutationError: MockAnnouncementError.boom
        )
        let store = AnnouncementsStore(apiClient: mock)
        await store.loadAdmin()

        do {
            _ = try await store.update(id: originalId, fields: ["title": .string("New")])
            XCTFail("update should throw")
        } catch {
            XCTAssertEqual(store.adminAnnouncements.first?.title, "Old", "Optimistic mutation should revert.")
            XCTAssertNotNil(store.lastWriteError)
        }
    }

    func test_update_unknownIdThrows() async {
        let store = AnnouncementsStore(apiClient: MockAnnouncementsAPIClient())

        do {
            _ = try await store.update(id: UUID(), fields: ["title": .string("nope")])
            XCTFail("update with unknown id should throw")
        } catch {
            XCTAssertTrue(error is AnnouncementsStoreError)
        }
    }

    // MARK: - Admin delete

    func test_delete_softFlipAndDropsFromPublic() async throws {
        let id = UUID()
        let original = makeAnnouncement(id: id, isActive: true)
        let deleted = LeagueAnnouncement(
            id: id,
            title: original.title,
            body: original.body,
            priority: original.priority,
            expiresAt: original.expiresAt,
            isActive: false,
            displayOrder: original.displayOrder
        )
        let mock = MockAnnouncementsAPIClient(
            publicResponse: AnnouncementsListResponse(success: true, count: 1, rows: [original]),
            adminResponse: AdminAnnouncementsListResponse(success: true, count: 1, rows: [original], tableMissing: false),
            mutationResponse: AnnouncementMutationResponse(success: true, row: deleted)
        )
        let store = AnnouncementsStore(apiClient: mock)
        await store.load()
        await store.loadAdmin()
        XCTAssertEqual(store.announcements.count, 1)

        try await store.delete(id: id)

        XCTAssertEqual(store.adminAnnouncements.first?.isActive, false)
        XCTAssertTrue(store.announcements.isEmpty, "Public list should drop the deleted row.")
    }

    func test_delete_revertsOnError() async {
        let id = UUID()
        let original = makeAnnouncement(id: id, isActive: true)
        let mock = MockAnnouncementsAPIClient(
            publicResponse: AnnouncementsListResponse(success: true, count: 1, rows: [original]),
            adminResponse: AdminAnnouncementsListResponse(success: true, count: 1, rows: [original], tableMissing: false),
            mutationError: MockAnnouncementError.boom
        )
        let store = AnnouncementsStore(apiClient: mock)
        await store.load()
        await store.loadAdmin()

        do {
            try await store.delete(id: id)
            XCTFail("delete should throw")
        } catch {
            XCTAssertEqual(store.adminAnnouncements.first?.isActive, true, "Soft-delete flip should revert.")
            XCTAssertEqual(store.announcements.count, 1, "Public list should be restored.")
            XCTAssertNotNil(store.lastWriteError)
        }
    }
}

// MARK: - Mock

final class MockAnnouncementsAPIClient: XomperAPIClientProtocol, @unchecked Sendable {
    var publicResponse: AnnouncementsListResponse?
    var publicError: Error?
    var adminResponse: AdminAnnouncementsListResponse?
    var adminError: Error?
    var mutationResponse: AnnouncementMutationResponse?
    var mutationError: Error?

    private(set) var publicCallCount: Int = 0
    private(set) var adminCallCount: Int = 0
    private(set) var createCalls: [(title: String, body: String, priority: String, expiresAt: Date?, isActive: Bool, displayOrder: Int)] = []
    private(set) var updateCalls: [(id: UUID, fields: [String: AdminFieldValue])] = []
    private(set) var deleteCalls: [UUID] = []

    init(
        publicResponse: AnnouncementsListResponse? = nil,
        publicError: Error? = nil,
        adminResponse: AdminAnnouncementsListResponse? = nil,
        adminError: Error? = nil,
        mutationResponse: AnnouncementMutationResponse? = nil,
        mutationError: Error? = nil
    ) {
        self.publicResponse = publicResponse
        self.publicError = publicError
        self.adminResponse = adminResponse
        self.adminError = adminError
        self.mutationResponse = mutationResponse
        self.mutationError = mutationError
    }

    func fetchAnnouncements() async throws -> AnnouncementsListResponse {
        publicCallCount += 1
        if let err = publicError { throw err }
        return publicResponse ?? AnnouncementsListResponse(success: true, count: 0, rows: [])
    }

    func fetchAdminAnnouncements() async throws -> AdminAnnouncementsListResponse {
        adminCallCount += 1
        if let err = adminError { throw err }
        return adminResponse ?? AdminAnnouncementsListResponse(success: true, count: 0, rows: [], tableMissing: false)
    }

    func createAnnouncement(title: String, body: String, priority: String, expiresAt: Date?, isActive: Bool, displayOrder: Int) async throws -> AnnouncementMutationResponse {
        createCalls.append((title, body, priority, expiresAt, isActive, displayOrder))
        if let err = mutationError { throw err }
        guard let response = mutationResponse else { throw MockAnnouncementError.notConfigured }
        return response
    }

    func updateAnnouncement(id: UUID, fields: [String: AdminFieldValue]) async throws -> AnnouncementMutationResponse {
        updateCalls.append((id, fields))
        if let err = mutationError { throw err }
        guard let response = mutationResponse else { throw MockAnnouncementError.notConfigured }
        return response
    }

    func deleteAnnouncement(id: UUID) async throws -> AnnouncementMutationResponse {
        deleteCalls.append(id)
        if let err = mutationError { throw err }
        guard let response = mutationResponse else { throw MockAnnouncementError.notConfigured }
        return response
    }

    // MARK: - Unused protocol surface

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws { throw MockAnnouncementError.unsupported }
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw MockAnnouncementError.unsupported }
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw MockAnnouncementError.unsupported }
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws { throw MockAnnouncementError.unsupported }
    func registerDevice(userId: String, deviceToken: String) async throws { throw MockAnnouncementError.unsupported }
    func unregisterDevice(userId: String, deviceToken: String) async throws { throw MockAnnouncementError.unsupported }
    func adminListNotifications(sleeperUserId: String, daysBack: Int, kind: String?, status: String?, limit: Int) async throws -> AdminNotificationsResponse { throw MockAnnouncementError.unsupported }
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse { throw MockAnnouncementError.unsupported }
    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient] { throw MockAnnouncementError.unsupported }
    func sendTestEmail(recipientSleeperUserId: String, reportId: String) async throws -> TestEmailResponse { throw MockAnnouncementError.unsupported }
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? { nil }
    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse { AIReportsListResponse(rows: [], nextCursor: nil) }
    func fetchAIReportByPeriod(type: AIReportType, period: String) async throws -> AIReport? { nil }
    func fetchMockDrafts() async throws -> [AIReport] { [] }
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw MockAnnouncementError.unsupported }
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw MockAnnouncementError.unsupported }
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw MockAnnouncementError.unsupported }
    func setReportFlag(leagueId: String, reportType: AIReportType, period: String, flag: ReportFlag, value: Bool) async throws -> ReportFlagResponse { throw MockAnnouncementError.unsupported }
    func fetchWhitelistedUsers() async throws -> [WhitelistedUser] { throw MockAnnouncementError.unsupported }
    func updateWhitelistedUser(userId: String, fields: [String: AdminFieldValue]) async throws -> UserUpdateResponse { throw MockAnnouncementError.unsupported }
    func fetchAdminWhitelistedLeagues() async throws -> [WhitelistedLeague] { throw MockAnnouncementError.unsupported }
    func updateWhitelistedLeague(leagueId: String, fields: [String: AdminFieldValue]) async throws -> LeagueUpdateResponse { throw MockAnnouncementError.unsupported }
    func fetchAuditEntries(limit: Int, cursor: String?) async throws -> AuditListResponse { throw MockAnnouncementError.unsupported }
    func fetchLogEvents(logGroup: LogGroup, level: LogLevel?, search: String?, limit: Int, cursor: String?) async throws -> LogsQueryResponse { throw MockAnnouncementError.unsupported }
    func fetchCronSettings() async throws -> CronSettingsListResponse { throw MockAnnouncementError.unsupported }
    func updateCronSetting(cronKey: String, enabled: Bool?, testMode: Bool?) async throws -> CronSettingUpdateResponse { throw MockAnnouncementError.unsupported }
}

enum MockAnnouncementError: Error, LocalizedError {
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
