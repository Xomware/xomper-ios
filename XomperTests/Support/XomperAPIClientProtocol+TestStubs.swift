import Foundation
@testable import Xomper

/// Default implementations for the admin/email-archive corner of
/// `XomperAPIClientProtocol` so per-suite mocks don't each have to stub
/// methods they never exercise. Any mock that *does* care about one of
/// these overrides it with a concrete implementation, which wins over the
/// default below. Calling an un-overridden method throws so a test that
/// unexpectedly hits it fails loudly instead of silently returning junk.
///
/// Added when several protocol methods (`sendTestEmailTemplate`,
/// `triggerWeekPreviewAIReview`, `fetchEmailArchive*`,
/// `resendArchivedEmail`) landed on the protocol without the older mocks
/// being updated, which broke the whole test target's compilation.
enum TestStubError: Error { case notStubbed(String) }

extension XomperAPIClientProtocol {
    func sendTestEmailTemplate(
        kind: String,
        recipientSleeperUserId: String
    ) async throws -> TestEmailTemplateResponse {
        throw TestStubError.notStubbed("sendTestEmailTemplate")
    }

    func triggerWeekPreviewAIReview(
        week: Int?,
        dryRun: Bool,
        force: Bool,
        seasonsBack: Int?
    ) async throws -> AIReviewTriggerResponse {
        throw TestStubError.notStubbed("triggerWeekPreviewAIReview")
    }

    func fetchEmailArchive(
        limit: Int,
        cursor: String?,
        recipient: String?,
        template: String?
    ) async throws -> EmailArchiveListResponse {
        throw TestStubError.notStubbed("fetchEmailArchive")
    }

    func fetchEmailArchiveDetail(id: String) async throws -> EmailArchiveEntry {
        throw TestStubError.notStubbed("fetchEmailArchiveDetail")
    }

    func resendArchivedEmail(id: String, toEmail: String) async throws -> ResendEmailResponse {
        throw TestStubError.notStubbed("resendArchivedEmail")
    }
}
