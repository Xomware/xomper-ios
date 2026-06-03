import Foundation

/// Every email template the admin can fire from the Test Email screen.
///
/// Three of these (`aiReviewPostDraft`, `aiReviewPreseason`,
/// `aiReviewWeekly`) route through the existing
/// `POST /admin/email-test` endpoint which re-sends a stored
/// `xomper-ai-reports` row. The remaining seven route through
/// `POST /admin/email-test-template` which composes a fresh sample
/// against fixture data (the production crons for these gate on NFL
/// `season_type == regular | post`, so offseason testing has to
/// bypass the data pipeline).
///
/// `wireValue` is the string the backend's `kind` dispatch table
/// expects. Keep these in sync with
/// `lambdas/api_admin_email_test_template/handler.py::_BUILDERS`.
enum TestEmailKind: String, CaseIterable, Identifiable, Hashable {
    case aiReviewPostDraft
    case aiReviewPreseason
    case aiReviewWeekly
    case weeklyRecap
    case weekPreview
    case lineupNotSet
    case ruleProposed
    case ruleAccepted
    case ruleDenied
    case taxiStealLeague
    case taxiStealOwner

    var id: String { rawValue }

    /// Whether this kind reuses the existing AI Review test-send path
    /// (which needs a stored report id) vs. the new template path
    /// (which sends fixture data).
    var isAIReview: Bool {
        switch self {
        case .aiReviewPostDraft, .aiReviewPreseason, .aiReviewWeekly:
            true
        default:
            false
        }
    }

    /// Maps the AI Review variants to the underlying report type so
    /// the view can look up the latest matching report from
    /// `AIReviewStore.latestByType`.
    var aiReportType: AIReportType? {
        switch self {
        case .aiReviewPostDraft: .postDraft
        case .aiReviewPreseason: .preseason
        case .aiReviewWeekly:    .weekly
        default: nil
        }
    }

    /// Wire value sent to the backend's `kind` field.
    var wireValue: String {
        switch self {
        case .aiReviewPostDraft:  "ai_review_postdraft"
        case .aiReviewPreseason:  "ai_review_preseason"
        case .aiReviewWeekly:     "ai_review_weekly"
        case .weeklyRecap:        "weekly_recap"
        case .weekPreview:        "week_preview"
        case .lineupNotSet:       "lineup_not_set"
        case .ruleProposed:       "rule_proposed"
        case .ruleAccepted:       "rule_accepted"
        case .ruleDenied:         "rule_denied"
        case .taxiStealLeague:    "taxi_steal_league"
        case .taxiStealOwner:     "taxi_steal_owner"
        }
    }

    var displayName: String {
        switch self {
        case .aiReviewPostDraft:  "AI Review — Post Draft"
        case .aiReviewPreseason:  "AI Review — Preseason"
        case .aiReviewWeekly:     "AI Review — Weekly Recap"
        case .weeklyRecap:        "Weekly Recap (non-AI)"
        case .weekPreview:        "Week Preview (Wed newsletter)"
        case .lineupNotSet:       "Lineup Not Set"
        case .ruleProposed:       "Rule Proposed"
        case .ruleAccepted:       "Rule Accepted"
        case .ruleDenied:         "Rule Denied"
        case .taxiStealLeague:    "Taxi Steal — League"
        case .taxiStealOwner:     "Taxi Steal — Owner"
        }
    }

    var systemImage: String {
        switch self {
        case .aiReviewPostDraft, .aiReviewPreseason, .aiReviewWeekly:
            "sparkles"
        case .weeklyRecap, .lineupNotSet:
            "calendar.badge.exclamationmark"
        case .weekPreview:
            "calendar.badge.clock"
        case .ruleProposed, .ruleAccepted, .ruleDenied:
            "checkmark.bubble.fill"
        case .taxiStealLeague, .taxiStealOwner:
            "bus.fill"
        }
    }
}
