import XCTest
@testable import Xomper

/// F2 — verifies `AdminStore.lastPreviewsByType` populates after each
/// successful dry-run trigger, and that broadcast (non-dry-run)
/// responses don't pollute the dictionary. Reuses
/// `MockAdminAPIClient` from `AdminStoreTests.swift`.
@MainActor
final class AdminStorePreviewTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTriggerResponse(
        reportType: AIReportType,
        dryRun: Bool,
        previewNames: [String]?
    ) -> AIReviewTriggerResponse {
        let previewsJson: String
        if let previewNames {
            let rows = previewNames.enumerated().map { (idx, name) in
                """
                {
                  "recipient_user_id": "U\(idx)",
                  "recipient_email": "u\(idx)@x.com",
                  "display_name": "\(name)",
                  "subject": "Subject for \(name)",
                  "text_body": "Body for \(name)",
                  "html_body_excerpt": "<html>\(name)</html>"
                }
                """
            }.joined(separator: ",")
            previewsJson = ", \"previews\": [\(rows)]"
        } else {
            previewsJson = ""
        }

        let typeId: String
        switch reportType {
        case .postDraft: typeId = "postDraft#2026"
        case .preseason: typeId = "preseason#2026-PRESEASON"
        case .weekly:    typeId = "weekly#2026W04"
        case .mock:      typeId = "mock#test"
        }

        let json = """
        {
          "report_id": "L1|REPORT#\(typeId)",
          "dry_run": \(dryRun),
          "delivery_count": \(previewNames?.count ?? 12),
          "model": "claude-haiku-4-5",
          "token_usage": { "input_tokens": 100, "output_tokens": 50 }\(previewsJson)
        }
        """
        return try! JSONDecoder().decode(
            AIReviewTriggerResponse.self,
            from: Data(json.utf8)
        )
    }

    // MARK: - Post-draft populates previews

    func testTriggerPostDraft_populatesLastPreviewsByType() async throws {
        let response = makeTriggerResponse(
            reportType: .postDraft,
            dryRun: true,
            previewNames: ["Adam", "Beth", "Mike"]
        )
        let mock = MockAdminAPIClient(triggerResponse: response)
        let store = AdminStore(apiClient: mock)

        _ = try await store.triggerPostDraft(dryRun: true, force: false)

        XCTAssertEqual(store.lastPreviewsByType[.postDraft]?.count, 3)
        XCTAssertEqual(
            store.lastPreviewsByType[.postDraft]?.map(\.displayName),
            ["Adam", "Beth", "Mike"]
        )
        // Other types untouched.
        XCTAssertNil(store.lastPreviewsByType[.preseason])
        XCTAssertNil(store.lastPreviewsByType[.weekly])
    }

    /// Broadcast responses leave `previews == nil`. Critically, the
    /// store must NOT overwrite a previously-populated preview set
    /// with an empty one — that would erase what the admin scanned
    /// just before hitting Broadcast.
    func testTriggerPostDraft_broadcastDoesNotPollutePreviews() async throws {
        // 1) Dry-run populates 12 previews.
        let dryResponse = makeTriggerResponse(
            reportType: .postDraft,
            dryRun: true,
            previewNames: (0..<12).map { "User\($0)" }
        )
        let mock = MockAdminAPIClient(triggerResponse: dryResponse)
        let store = AdminStore(apiClient: mock)

        _ = try await store.triggerPostDraft(dryRun: true, force: false)
        XCTAssertEqual(store.lastPreviewsByType[.postDraft]?.count, 12)

        // 2) Broadcast — same mock but swap in a response w/o previews.
        let broadcastResponse = makeTriggerResponse(
            reportType: .postDraft,
            dryRun: false,
            previewNames: nil
        )
        mock.triggerResponse = broadcastResponse

        _ = try await store.triggerPostDraft(dryRun: false, force: true)

        // Previews stay intact so the admin can still see what went out.
        XCTAssertEqual(store.lastPreviewsByType[.postDraft]?.count, 12)
    }

    // MARK: - Preseason populates previews

    func testTriggerPreseason_populatesLastPreviewsByType() async throws {
        let response = makeTriggerResponse(
            reportType: .preseason,
            dryRun: true,
            previewNames: ["Adam", "Beth"]
        )
        let mock = MockAdminAPIClient(preseasonTriggerResponse: response)
        let store = AdminStore(apiClient: mock)

        _ = try await store.triggerPreseason(dryRun: true, force: false)

        XCTAssertEqual(store.lastPreviewsByType[.preseason]?.count, 2)
        XCTAssertNil(store.lastPreviewsByType[.postDraft])
    }

    // MARK: - Weekly populates previews

    func testTriggerWeekly_populatesLastPreviewsByType() async throws {
        let response = makeTriggerResponse(
            reportType: .weekly,
            dryRun: true,
            previewNames: ["Adam"]
        )
        let mock = MockAdminAPIClient(weeklyTriggerResponse: response)
        let store = AdminStore(apiClient: mock)

        _ = try await store.triggerWeekly(week: 4, dryRun: true, force: false)

        XCTAssertEqual(store.lastPreviewsByType[.weekly]?.count, 1)
        XCTAssertEqual(store.lastPreviewsByType[.weekly]?.first?.displayName, "Adam")
    }

    // MARK: - clearPreviews

    func testClearPreviews_removesKey() async throws {
        let response = makeTriggerResponse(
            reportType: .postDraft,
            dryRun: true,
            previewNames: ["Adam"]
        )
        let mock = MockAdminAPIClient(triggerResponse: response)
        let store = AdminStore(apiClient: mock)

        _ = try await store.triggerPostDraft(dryRun: true, force: false)
        XCTAssertNotNil(store.lastPreviewsByType[.postDraft])

        store.clearPreviews(for: .postDraft)

        XCTAssertNil(store.lastPreviewsByType[.postDraft])
    }

    // MARK: - Cross-type isolation

    /// Trigger postDraft then preseason; both keys should exist and
    /// neither should overwrite the other.
    func testCrossTypeIsolation_keysCoexist() async throws {
        let postDraftResponse = makeTriggerResponse(
            reportType: .postDraft,
            dryRun: true,
            previewNames: ["Adam", "Beth"]
        )
        let preseasonResponse = makeTriggerResponse(
            reportType: .preseason,
            dryRun: true,
            previewNames: ["Carlos"]
        )
        let mock = MockAdminAPIClient(
            triggerResponse: postDraftResponse,
            preseasonTriggerResponse: preseasonResponse
        )
        let store = AdminStore(apiClient: mock)

        _ = try await store.triggerPostDraft(dryRun: true, force: false)
        _ = try await store.triggerPreseason(dryRun: true, force: false)

        XCTAssertEqual(store.lastPreviewsByType[.postDraft]?.count, 2)
        XCTAssertEqual(store.lastPreviewsByType[.preseason]?.count, 1)
        XCTAssertEqual(
            store.lastPreviewsByType[.preseason]?.first?.displayName,
            "Carlos"
        )
    }
}
