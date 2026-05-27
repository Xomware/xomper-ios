import XCTest
@testable import Xomper

@MainActor
final class AIReviewStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func makeReport(
        id: String = "L1|REPORT#weekly#2026W04",
        type: AIReportType = .weekly,
        period: String = "2026W04",
        createdAt: Date = Date()
    ) -> AIReport {
        AIReport(
            id: id,
            leagueId: "L1",
            reportType: type,
            period: period,
            bodyMarkdown: "## Recap\nWho lost. Who won. Tough week for Tony.",
            metadata: [:],
            createdAt: createdAt,
            model: "claude-haiku-4-5",
            promptVersion: "f0-2026-05-21"
        )
    }

    // MARK: - Test 1: loadLatest populates latestByType for postDraft

    func testLoadLatest_populatesLatestByType_forPostDraft() async {
        let report = makeReport(
            id: "L1|REPORT#postDraft#2026-POSTDRAFT",
            type: .postDraft,
            period: "2026-POSTDRAFT"
        )
        let mock = MockXomperAPIClient(latest: [.postDraft: report])
        let store = AIReviewStore(apiClient: mock)

        await store.loadLatest(type: .postDraft)

        XCTAssertEqual(store.latestByType[.postDraft]?.id, report.id)
        XCTAssertNil(store.error)
        XCTAssertEqual(mock.latestCalls.count, 1)
        XCTAssertEqual(mock.latestCalls.first, .postDraft)
    }

    // MARK: - Test 2: loadArchive populates archive

    func testLoadArchive_populatesArchive() async {
        let r1 = makeReport(id: "L1|REPORT#weekly#2026W04", period: "2026W04")
        let r2 = makeReport(id: "L1|REPORT#weekly#2026W03", period: "2026W03")
        let mock = MockXomperAPIClient(listPages: [
            (rows: [r1, r2], cursor: nil)
        ])
        let store = AIReviewStore(apiClient: mock)

        await store.loadArchive()

        XCTAssertEqual(store.archive.count, 2)
        XCTAssertEqual(store.archive.map(\.id), [r1.id, r2.id])
        XCTAssertNil(store.archiveCursor)
        XCTAssertFalse(store.isLoading)
    }

    // MARK: - Test 3: loadMore appends without duplication and advances cursor

    func testLoadMore_appendsAndAdvancesCursor() async {
        let r1 = makeReport(id: "L1|REPORT#weekly#2026W04", period: "2026W04")
        let r2 = makeReport(id: "L1|REPORT#weekly#2026W03", period: "2026W03")
        let r3 = makeReport(id: "L1|REPORT#weekly#2026W02", period: "2026W02")
        // r2 deliberately repeated across pages to verify de-dup
        // (cursor walks back through the GSI; overlap is harmless).
        let mock = MockXomperAPIClient(listPages: [
            (rows: [r1, r2], cursor: "cursor-1"),
            (rows: [r2, r3], cursor: nil)
        ])
        let store = AIReviewStore(apiClient: mock)

        await store.loadArchive()
        XCTAssertEqual(store.archive.count, 2)
        XCTAssertEqual(store.archiveCursor, "cursor-1")

        await store.loadMore()
        XCTAssertEqual(store.archive.count, 3, "r2 should not be duplicated")
        XCTAssertEqual(store.archive.map(\.id), [r1.id, r2.id, r3.id])
        XCTAssertNil(store.archiveCursor)
    }

    // MARK: - Test 4: 12-hour freshness skip

    func testLoadLatest_skipsWithinFreshnessWindow() async {
        let report = makeReport()
        let mock = MockXomperAPIClient(latest: [.weekly: report])
        let store = AIReviewStore(apiClient: mock)

        await store.loadLatest(type: .weekly)
        XCTAssertEqual(mock.latestCalls.count, 1)

        // Second call within 12h — must be skipped.
        await store.loadLatest(type: .weekly)
        XCTAssertEqual(mock.latestCalls.count, 1, "Should short-circuit inside the 12-hour window")

        // Forced refresh — must re-fetch.
        await store.loadLatest(type: .weekly, force: true)
        XCTAssertEqual(mock.latestCalls.count, 2)
    }

    // MARK: - Test 5: loadMore no-ops when cursor is nil

    func testLoadMore_noopWhenCursorIsNil() async {
        let mock = MockXomperAPIClient(listPages: [
            (rows: [makeReport()], cursor: nil)
        ])
        let store = AIReviewStore(apiClient: mock)

        await store.loadArchive()
        let listCallsBefore = mock.listCalls.count

        await store.loadMore()
        XCTAssertEqual(mock.listCalls.count, listCallsBefore, "loadMore should be a no-op when cursor is nil")
    }

    // MARK: - Test 6a: loadMockDrafts populates mockDrafts

    func testLoadMockDrafts_populatesMockDrafts() async {
        let r1 = makeReport(
            id: "L1|REPORT#mock#2026-bpa",
            type: .mock,
            period: "2026-bpa"
        )
        let r2 = makeReport(
            id: "L1|REPORT#mock#2026-team-fit",
            type: .mock,
            period: "2026-team-fit"
        )
        let r3 = makeReport(
            id: "L1|REPORT#mock#2026-wildcard",
            type: .mock,
            period: "2026-wildcard"
        )
        let mock = MockXomperAPIClient(
            listPagesByType: [
                AIReportType.mock.rawValue: [(rows: [r1, r2, r3], cursor: nil)]
            ]
        )
        let store = AIReviewStore(apiClient: mock)

        await store.loadMockDrafts()

        XCTAssertEqual(store.mockDrafts.count, 3)
        XCTAssertEqual(store.mockDrafts.map(\.period), ["2026-bpa", "2026-team-fit", "2026-wildcard"])
        XCTAssertNil(store.mockDraftsError)
        XCTAssertEqual(mock.mockDraftsCallCount, 1)
    }

    // MARK: - Test 6b: loadMockDrafts short-circuits within freshness window

    func testLoadMockDrafts_skipsWithinFreshnessWindow() async {
        let r1 = makeReport(
            id: "L1|REPORT#mock#2026-bpa",
            type: .mock,
            period: "2026-bpa"
        )
        let mock = MockXomperAPIClient(
            listPagesByType: [
                AIReportType.mock.rawValue: [(rows: [r1], cursor: nil)]
            ]
        )
        let store = AIReviewStore(apiClient: mock)

        await store.loadMockDrafts()
        XCTAssertEqual(mock.mockDraftsCallCount, 1)

        await store.loadMockDrafts()
        XCTAssertEqual(mock.mockDraftsCallCount, 1, "Should short-circuit inside the 12-hour window")

        await store.loadMockDrafts(force: true)
        XCTAssertEqual(mock.mockDraftsCallCount, 2)
    }

    // MARK: - Test 6c: loadWeeklyReport caches by period

    func testLoadWeeklyReport_cachesByPeriod() async {
        let r = makeReport(
            id: "L1|REPORT#weekly#2025W04",
            type: .weekly,
            period: "2025W04"
        )
        let mock = MockXomperAPIClient(
            reportsByPeriod: ["2025W04": r]
        )
        let store = AIReviewStore(apiClient: mock)

        await store.loadWeeklyReport(period: "2025W04")
        XCTAssertEqual(store.weeklyReportsByPeriod["2025W04"]?.id, r.id)
        XCTAssertEqual(mock.byPeriodCalls.count, 1)

        // Second call for the same period — must short-circuit.
        await store.loadWeeklyReport(period: "2025W04")
        XCTAssertEqual(mock.byPeriodCalls.count, 1, "Cached period should not refetch")

        // Different period — must fetch.
        await store.loadWeeklyReport(period: "2025W05")
        XCTAssertEqual(mock.byPeriodCalls.count, 2)
    }

    // MARK: - Test 6d: loadWeeklyReport ignores empty period

    func testLoadWeeklyReport_ignoresEmptyPeriod() async {
        let mock = MockXomperAPIClient()
        let store = AIReviewStore(apiClient: mock)

        await store.loadWeeklyReport(period: "")
        XCTAssertEqual(mock.byPeriodCalls.count, 0)
    }

    // MARK: - Test 7: mostRecentLatest picks newest across types

    func testMostRecentLatest_picksNewestAcrossTypes() async {
        let older = makeReport(
            id: "L1|REPORT#preseason#2026-PRE",
            type: .preseason,
            period: "2026-PRE",
            createdAt: Date(timeIntervalSinceNow: -86_400 * 30)
        )
        let newer = makeReport(
            id: "L1|REPORT#weekly#2026W01",
            type: .weekly,
            period: "2026W01",
            createdAt: Date(timeIntervalSinceNow: -86_400)
        )
        let mock = MockXomperAPIClient(latest: [
            .preseason: older,
            .weekly: newer
        ])
        let store = AIReviewStore(apiClient: mock)

        await store.loadLatest(type: .preseason)
        await store.loadLatest(type: .weekly)

        XCTAssertEqual(store.mostRecentLatest?.id, newer.id)
    }
}

// MARK: - Mock API Client

/// Sendable mock for AI Review endpoints only. Other protocol methods
/// throw to ensure they aren't accidentally exercised by these tests.
final class MockXomperAPIClient: XomperAPIClientProtocol, @unchecked Sendable {
    var latest: [AIReportType: AIReport]
    var listPages: [(rows: [AIReport], cursor: String?)]
    /// Pages returned by `fetchAIReportsList` when a `type` filter is
    /// passed. Keys are stringly the rawValue so tests don't need to
    /// reach into the enum. Falls back to the unfiltered `listPages`
    /// queue when no type-specific override is registered.
    var listPagesByType: [String: [(rows: [AIReport], cursor: String?)]]
    private var listPageIndexByType: [String: Int] = [:]
    /// `(period, report)` rows returned by `fetchAIReportByPeriod`.
    var reportsByPeriod: [String: AIReport]

    private(set) var latestCalls: [AIReportType] = []
    private(set) var listCalls: [(type: AIReportType?, limit: Int, cursor: String?)] = []
    private(set) var byPeriodCalls: [(type: AIReportType, period: String)] = []
    private(set) var mockDraftsCallCount = 0
    private var listPageIndex = 0

    init(
        latest: [AIReportType: AIReport] = [:],
        listPages: [(rows: [AIReport], cursor: String?)] = [],
        listPagesByType: [String: [(rows: [AIReport], cursor: String?)]] = [:],
        reportsByPeriod: [String: AIReport] = [:]
    ) {
        self.latest = latest
        self.listPages = listPages
        self.listPagesByType = listPagesByType
        self.reportsByPeriod = reportsByPeriod
    }

    // MARK: AI Review

    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? {
        latestCalls.append(type)
        return latest[type]
    }

    func fetchAIReportsList(
        type: AIReportType?,
        limit: Int,
        cursor: String?
    ) async throws -> AIReportsListResponse {
        listCalls.append((type, limit, cursor))
        if let type, let pages = listPagesByType[type.rawValue] {
            let idx = listPageIndexByType[type.rawValue] ?? 0
            guard idx < pages.count else {
                return AIReportsListResponse(rows: [], nextCursor: nil)
            }
            let page = pages[idx]
            listPageIndexByType[type.rawValue] = idx + 1
            return AIReportsListResponse(rows: page.rows, nextCursor: page.cursor)
        }
        guard listPageIndex < listPages.count else {
            return AIReportsListResponse(rows: [], nextCursor: nil)
        }
        let page = listPages[listPageIndex]
        listPageIndex += 1
        return AIReportsListResponse(rows: page.rows, nextCursor: page.cursor)
    }

    func fetchAIReportByPeriod(type: AIReportType, period: String) async throws -> AIReport? {
        byPeriodCalls.append((type, period))
        return reportsByPeriod[period]
    }

    func fetchMockDrafts() async throws -> [AIReport] {
        mockDraftsCallCount += 1
        return listPagesByType[AIReportType.mock.rawValue]?.flatMap(\.rows) ?? []
    }

    // MARK: Unused protocol surface — throw to catch accidental calls

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws { throw Unsupported.method }
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw Unsupported.method }
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws { throw Unsupported.method }
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws { throw Unsupported.method }
    func registerDevice(userId: String, deviceToken: String) async throws { throw Unsupported.method }
    func unregisterDevice(userId: String, deviceToken: String) async throws { throw Unsupported.method }
    func adminListNotifications(sleeperUserId: String, daysBack: Int, kind: String?, status: String?, limit: Int) async throws -> AdminNotificationsResponse { throw Unsupported.method }
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse { throw Unsupported.method }
    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient] { throw Unsupported.method }
    func sendTestEmail(recipientSleeperUserId: String, reportId: String) async throws -> TestEmailResponse { throw Unsupported.method }
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw Unsupported.method }
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw Unsupported.method }
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse { throw Unsupported.method }

    enum Unsupported: Error { case method }
}

