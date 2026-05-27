import Foundation

/// One rendered email preview returned by the three dry-run trigger
/// endpoints (`/admin/ai-review-{postdraft,preseason,weekly}-trigger`).
///
/// Backend renders these via the same `build_email_payload` helper that
/// the real broadcast path uses, so what the admin sees in the iOS
/// preview list is exactly what would be delivered if they hit
/// "Broadcast to all 12".
///
/// Wire shape (snake_case from the backend, server pre-sorts by
/// `display_name` ascending):
/// ```json
/// {
///   "recipient_user_id": "U123",
///   "recipient_email": "user@example.com",
///   "display_name": "Adam",
///   "subject": "Week 4 Recap — 2026W04",
///   "text_body": "..." // capped at 4096 chars server-side
///   "html_body_excerpt": "..." // capped at 500 chars server-side
/// }
/// ```
///
/// Notes:
/// - Server omits `html_body` entirely to keep payload <60KB for 12
///   recipients. Only the excerpt comes over the wire.
/// - `id` is derived from `recipientUserId` so SwiftUI `ForEach` /
///   `.sheet(item:)` can use the struct directly.
/// - F2 deliverable — see `docs/features/admin-portal/f2-preview/PLAN.md`.
struct EmailPreview: Codable, Sendable, Identifiable, Hashable {
    let recipientUserId: String
    let recipientEmail: String
    let displayName: String
    let subject: String
    let textBody: String
    let htmlBodyExcerpt: String

    var id: String { recipientUserId }

    enum CodingKeys: String, CodingKey {
        case recipientUserId = "recipient_user_id"
        case recipientEmail = "recipient_email"
        case displayName = "display_name"
        case subject
        case textBody = "text_body"
        case htmlBodyExcerpt = "html_body_excerpt"
    }
}
