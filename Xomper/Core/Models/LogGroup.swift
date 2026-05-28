import Foundation

/// Allowlisted CloudWatch log group slugs the iOS Log Viewer (F5) can
/// query via `GET /admin/logs-query`. The raw value is the slug the
/// backend expects on the wire (it maps the slug to a full
/// `/aws/lambda/...` log group name in `ADMIN_LOG_GROUP_ALLOWLIST`).
///
/// Using a closed enum on the client guarantees the iOS picker can
/// never send an off-allowlist value — the backend would 400 anyway,
/// but doing it in the type system saves a round-trip.
///
/// Friendly `displayName`s are pinned in the F5 plan and mirror the
/// labels used in the picker. New admin lambdas added in future
/// epics need both an entry here AND in the backend's
/// `ADMIN_LOG_GROUP_ALLOWLIST` (plus the IAM role's ARN list).
enum LogGroup: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case aiReviewPostdraft  = "ai-review-postdraft"
    case aiReviewPreseason  = "ai-review-preseason"
    case aiReviewWeekly     = "ai-review-weekly"
    case aiReviewWeeklyCron = "ai-review-weekly-cron"
    case weeklyRecap        = "weekly-recap"
    case emailTest          = "email-test"
    case reportsFlag        = "reports-flag"
    case usersUpdate        = "users-update"
    case leaguesUpdate      = "leagues-update"
    case auditList          = "audit-list"

    var id: String { rawValue }

    /// Human-friendly label rendered in the picker. Pinned to the F5
    /// plan's resolved labels (BRAINSTORM.md Q6).
    var displayName: String {
        switch self {
        case .aiReviewPostdraft:  return "Post-Draft AI Review"
        case .aiReviewPreseason:  return "Preseason AI Review"
        case .aiReviewWeekly:     return "Weekly AI Review (admin trigger)"
        case .aiReviewWeeklyCron: return "Weekly AI Review (cron)"
        case .weeklyRecap:        return "Weekly Recap (legacy)"
        case .emailTest:          return "Test Email"
        case .reportsFlag:        return "Reports Flag"
        case .usersUpdate:        return "Users Update"
        case .leaguesUpdate:      return "Leagues Update"
        case .auditList:          return "Audit List"
        }
    }
}
