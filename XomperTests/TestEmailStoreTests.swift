import XCTest
@testable import Xomper

@MainActor
final class TestEmailStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func makeRecipient(
        userId: String = "U1",
        name: String = "Test User",
        email: String = "test@example.com",
        isAdmin: Bool = false
    ) -> TestEmailRecipient {
        TestEmailRecipient(
            userId: userId,
            displayName: name,
            email: email,
            isAdmin: isAdmin
        )
    }

    private func makeReport() -> AIReport {
        AIReport(
            id: "LEAGUE#L1|REPORT#weekly#2026W04",
            leagueId: "L1",
            reportType: .weekly,
            period: "2026W04",
            bodyMarkdown: "## Week 4\nGreat games.",
            createdAt: Date()
        )
    }

    private func makeResponse(
        email: String = "test@example.com",
        messageId: String? = "ses-mid-abc",
        template: String = "ai_review_test",
        reportType: String = "weekly",
        reportPeriod: String = "2026W04"
    ) -> TestEmailResponse {
        TestEmailResponse(
            recipientEmail: email,
            messageId: messageId,
            sentAt: "2026-05-26T17:42:33Z",
            template: template,
            reportType: reportType,
            reportPeriod: reportPeriod
        )
    }

    // MARK: - loadRecipients

    func testLoadRecipients_populatesFromMock() async {
        let recipients = [
            makeRecipient(userId: "U1", name: "Alice", email: "alice@example.com", isAdmin: true),
            makeRecipient(userId: "U2", name: "Bob", email: "bob@example.com"),
        ]
        let mock = MockTestEmailAPIClient(recipients: recipients)
        let store = TestEmailStore(apiClient: mock)

        await store.loadRecipients()

        XCTAssertEqual(store.recipients.count, 2)
        XCTAssertEqual(store.recipients.first?.displayName, "Alice")
        XCTAssertTrue(store.recipients.first?.isAdmin ?? false)
        XCTAssertNil(store.recipientsError)
        XCTAssertFalse(store.isLoadingRecipients)
    }

    func testLoadRecipients_surfacesError() async {
        let mock = MockTestEmailAPIClient(recipientsError: TestEmailMockError.boom)
        let store = TestEmailStore(apiClient: mock)

        await store.loadRecipients()

        XCTAssertTrue(store.recipients.isEmpty)
        XCTAssertNotNil(store.recipientsError)
    }

    // MARK: - sendTest no-op guards

    func testSendTest_noopWhenNoSelections() async {
        let mock = MockTestEmailAPIClient()
        let store = TestEmailStore(apiClient: mock)

        // Both pickers nil — should silently no-op.
        await store.sendTest(sleeperUserId: "ADMIN")

        XCTAssertEqual(mock.sendCalls.count, 0)
        XCTAssertNil(store.lastResult)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isSending)
    }

    func testSendTest_noopWhenOnlyRecipientSelected() async {
        let mock = MockTestEmailAPIClient()
        let store = TestEmailStore(apiClient: mock)
        store.selectedRecipient = makeRecipient()

        await store.sendTest(sleeperUserId: "ADMIN")

        XCTAssertEqual(mock.sendCalls.count, 0)
        XCTAssertNil(store.lastResult)
    }

    // MARK: - sendTest happy path

    func testSendTest_successPopulatesLastResult() async {
        let response = makeResponse()
        let mock = MockTestEmailAPIClient(sendResponse: response)
        let store = TestEmailStore(apiClient: mock)

        let recipient = makeRecipient()
        let report = makeReport()

        await store.sendTest(
            report: report,
            recipient: recipient,
            sleeperUserId: ""
        )

        XCTAssertEqual(mock.sendCalls.count, 1)
        XCTAssertEqual(mock.sendCalls.first?.userId, "U1")
        XCTAssertEqual(mock.sendCalls.first?.reportId, "LEAGUE#L1|REPORT#weekly#2026W04")
        XCTAssertEqual(store.lastResult?.recipientEmail, "test@example.com")
        XCTAssertEqual(store.lastResult?.template, "ai_review_test")
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isSending)
    }

    // MARK: - sendTest failure

    func testSendTest_failureSurfacesError() async {
        let mock = MockTestEmailAPIClient(sendError: TestEmailMockError.boom)
        let store = TestEmailStore(apiClient: mock)

        await store.sendTest(
            report: makeReport(),
            recipient: makeRecipient(),
            sleeperUserId: ""
        )

        XCTAssertEqual(mock.sendCalls.count, 1)
        XCTAssertNil(store.lastResult)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isSending)
    }

    // MARK: - reset

    func testReset_clearsResultAndError() async {
        let mock = MockTestEmailAPIClient(sendResponse: makeResponse())
        let store = TestEmailStore(apiClient: mock)
        await store.sendTest(
            report: makeReport(),
            recipient: makeRecipient(),
            sleeperUserId: ""
        )
        XCTAssertNotNil(store.lastResult)

        store.reset()

        XCTAssertNil(store.lastResult)
        XCTAssertNil(store.lastError)
    }

    // MARK: - Wire format guard

    func testTestEmailResponse_decodesSnakeCase() throws {
        let json = """
        {
            "recipient_email": "test@example.com",
            "message_id": "ses-mid-xyz",
            "sent_at": "2026-05-26T17:42:33Z",
            "template": "ai_review_test",
            "report_type": "weekly",
            "report_period": "2026W04"
        }
        """
        let decoded = try JSONDecoder().decode(
            TestEmailResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.recipientEmail, "test@example.com")
        XCTAssertEqual(decoded.messageId, "ses-mid-xyz")
        XCTAssertEqual(decoded.reportType, "weekly")
        XCTAssertEqual(decoded.reportPeriod, "2026W04")
    }

    func testTestEmailRecipient_decodesSnakeCase() throws {
        let json = """
        {
            "user_id": "U1",
            "display_name": "Alice",
            "email": "alice@example.com",
            "is_admin": true
        }
        """
        let decoded = try JSONDecoder().decode(
            TestEmailRecipient.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.userId, "U1")
        XCTAssertEqual(decoded.displayName, "Alice")
        XCTAssertEqual(decoded.email, "alice@example.com")
        XCTAssertTrue(decoded.isAdmin)
        XCTAssertEqual(decoded.id, "U1")
    }
}

// MARK: - Mock API client

/// Tiny mock dedicated to TestEmailStore's two endpoints. Implements
/// the full protocol so the type checks; unused methods throw.
final class MockTestEmailAPIClient: XomperAPIClientProtocol, @unchecked Sendable {
    var recipients: [TestEmailRecipient]
    var recipientsError: Error?
    var sendResponse: TestEmailResponse?
    var sendError: Error?
    var notifications: AdminNotificationsResponse?

    private(set) var sendCalls: [(userId: String, reportId: String)] = []
    private(set) var fetchRecipientsCallCount = 0
    private(set) var listNotificationsCallCount = 0

    init(
        recipients: [TestEmailRecipient] = [],
        recipientsError: Error? = nil,
        sendResponse: TestEmailResponse? = nil,
        sendError: Error? = nil,
        notifications: AdminNotificationsResponse? = nil
    ) {
        self.recipients = recipients
        self.recipientsError = recipientsError
        self.sendResponse = sendResponse
        self.sendError = sendError
        self.notifications = notifications
    }

    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient] {
        fetchRecipientsCallCount += 1
        if let err = recipientsError { throw err }
        return recipients
    }

    func sendTestEmail(
        recipientSleeperUserId: String,
        reportId: String
    ) async throws -> TestEmailResponse {
        sendCalls.append((recipientSleeperUserId, reportId))
        if let err = sendError { throw err }
        guard let response = sendResponse else { throw TestEmailMockError.notConfigured }
        return response
    }

    func adminListNotifications(
        sleeperUserId: String,
        daysBack: Int,
        kind: String?,
        status: String?,
        limit: Int
    ) async throws -> AdminNotificationsResponse {
        listNotificationsCallCount += 1
        return notifications ?? AdminNotificationsResponse(rows: [], count: 0)
    }

    // MARK: Unused protocol surface

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws { throw TestEmailMockError.unsupported }
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw TestEmailMockError.unsupported }
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw TestEmailMockError.unsupported }
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws { throw TestEmailMockError.unsupported }
    func registerDevice(userId: String, deviceToken: String) async throws { throw TestEmailMockError.unsupported }
    func unregisterDevice(userId: String, deviceToken: String) async throws { throw TestEmailMockError.unsupported }
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse { throw TestEmailMockError.unsupported }
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? { nil }
    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse { AIReportsListResponse(rows: [], nextCursor: nil) }
    func fetchAIReportByPeriod(type: AIReportType, period: String) async throws -> AIReport? { nil }
    func fetchMockDrafts() async throws -> [AIReport] { [] }
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw TestEmailMockError.unsupported }
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw TestEmailMockError.unsupported }
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw TestEmailMockError.unsupported }
    func setReportFlag(leagueId: String, reportType: AIReportType, period: String, flag: ReportFlag, value: Bool) async throws -> ReportFlagResponse { throw TestEmailMockError.unsupported }
}

enum TestEmailMockError: Error, LocalizedError {
    case boom
    case unsupported
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .boom: "boom"
        case .unsupported: "mock method not supported"
        case .notConfigured: "mock send response not configured"
        }
    }
}
