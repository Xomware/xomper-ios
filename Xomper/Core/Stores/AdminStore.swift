import Foundation

/// Drives the iOS Admin portal. Reads the activity feed from
/// `/admin/notifications` and fires `/admin/test-send` test sends
/// for any of the production templates.
///
/// Admin gating is enforced on the backend (the `is_admin` column on
/// `whitelisted_users`). Client-side, we use
/// `LeagueStore.whitelistedLeague` /
/// `UserStore.myUser.isAdminFlagFromSupabase` (when wired) to decide
/// whether to show the destination at all — but every API call must
/// re-check on the server.
@Observable
@MainActor
final class AdminStore {
    private(set) var entries: [AdminNotificationLogEntry] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastTestResult: String?

    // MARK: - Post-Draft AI Review state

    /// Latest post-draft AI Review row from `/ai-reports/latest`.
    /// Drives the trigger card's status line + button label.
    /// `nil` until `loadPostDraftLatest()` runs (or if it errors).
    private(set) var postDraftLatest: AIReport?
    /// True while a trigger request is in flight. Disables the
    /// button and shows a spinner.
    private(set) var isTriggeringPostDraft = false
    /// Last error from the trigger flow. Cleared on next trigger.
    private(set) var postDraftError: Error?
    /// Last successful trigger response. Surfaces delivery count +
    /// model in the result line.
    private(set) var postDraftResult: AIReviewTriggerResponse?

    /// Two-way bound by the AdminView toggle. Defaults to true so
    /// the first run is always dry-run for tone calibration.
    var postDraftDryRun: Bool = true

    var filterKind: KindFilter = .all
    var filterStatus: StatusFilter = .all

    enum KindFilter: String, CaseIterable, Identifiable, Sendable {
        case all
        case push
        case email
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:   "All"
            case .push:  "Push"
            case .email: "Email"
            }
        }
        var apiValue: String? {
            switch self {
            case .all:   nil
            case .push:  "push"
            case .email: "email"
            }
        }
    }

    enum StatusFilter: String, CaseIterable, Identifiable, Sendable {
        case all
        case success
        case failure
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:     "All"
            case .success: "Success"
            case .failure: "Failure"
            }
        }
        var apiValue: String? {
            switch self {
            case .all:     nil
            case .success: "success"
            case .failure: "failure"
            }
        }
    }

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    func refresh(sleeperUserId: String) async {
        guard !sleeperUserId.isEmpty else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.adminListNotifications(
                sleeperUserId: sleeperUserId,
                daysBack: 7,
                kind: filterKind.apiValue,
                status: filterStatus.apiValue,
                limit: 200
            )
            entries = response.rows
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Post-Draft AI Review

    /// Reads the latest post-draft report so the trigger card can
    /// reflect whether a dry-run / broadcast already happened. Silent
    /// on failure — the card just defaults to "no report yet" copy.
    func loadPostDraftLatest() async {
        do {
            postDraftLatest = try await apiClient.fetchLatestAIReport(type: .postDraft)
        } catch {
            postDraftLatest = nil
        }
    }

    /// Fires the admin trigger endpoint. Surfaces the response in
    /// `postDraftResult` on success or `postDraftError` on failure,
    /// and re-reads `postDraftLatest` afterwards so the card label
    /// reflects the new state.
    ///
    /// Throws so callers can decide whether to surface the error
    /// further (e.g. for confirmation dialogs). Internal state is
    /// updated regardless.
    @discardableResult
    func triggerPostDraft(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse {
        isTriggeringPostDraft = true
        postDraftError = nil
        postDraftResult = nil
        defer { isTriggeringPostDraft = false }

        do {
            let response = try await apiClient.triggerPostDraftAIReview(
                dryRun: dryRun,
                force: force
            )
            postDraftResult = response
            // Refresh latest so the card label updates from "Generate"
            // to "Regenerate (force)" on next render.
            await loadPostDraftLatest()
            return response
        } catch {
            postDraftError = error
            throw error
        }
    }

    func sendTest(
        kind: AdminTestKind,
        sleeperUserId: String,
        email: String?,
        channels: [String]
    ) async {
        guard !sleeperUserId.isEmpty else {
            lastTestResult = "Missing sleeper_user_id"
            return
        }
        lastError = nil
        do {
            let response = try await apiClient.adminTestSend(
                sleeperUserId: sleeperUserId,
                email: email,
                kind: kind.rawValue,
                channels: channels
            )
            lastTestResult = "✓ \(kind.label) — push: \(response.pushSent), email: \(response.emailSent)"
            // Refresh feed so the new send appears.
            await refresh(sleeperUserId: sleeperUserId)
        } catch {
            lastTestResult = "✗ \(kind.label) — \(error.localizedDescription)"
        }
    }
}

/// Production templates that the admin portal can fire as test sends.
/// Mirrors the `kind` strings the backend `api_admin_test_send` handler
/// understands.
enum AdminTestKind: String, CaseIterable, Identifiable, Sendable {
    case lineupNotSet     = "lineup_not_set"
    case weeklyRecap      = "weekly_recap"
    case closeGameAlert   = "close_game_alert"
    case worldcupClinched = "worldcup_clinched"
    case worldcupEliminated = "worldcup_eliminated"
    case worldcupLineMoved = "worldcup_line_moved"
    case ruleProposed     = "rule_proposed"
    case ruleAccepted     = "rule_accepted"
    case ruleDenied       = "rule_denied"
    case taxiSteal        = "taxi_steal"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lineupNotSet:       "Lineup not set"
        case .weeklyRecap:        "Weekly recap"
        case .closeGameAlert:     "Close game alert"
        case .worldcupClinched:   "World Cup clinched"
        case .worldcupEliminated: "World Cup eliminated"
        case .worldcupLineMoved:  "World Cup line moved"
        case .ruleProposed:       "Rule proposed"
        case .ruleAccepted:       "Rule accepted"
        case .ruleDenied:         "Rule denied"
        case .taxiSteal:          "Taxi steal"
        }
    }

    /// Whether this template has both push + email legs in production.
    /// Drives whether the test-send button row gets a single "Push +
    /// email" button or two separate ones.
    var hasEmail: Bool {
        switch self {
        case .lineupNotSet, .weeklyRecap, .ruleProposed, .ruleAccepted, .ruleDenied:
            return true
        case .closeGameAlert, .worldcupClinched, .worldcupEliminated, .worldcupLineMoved, .taxiSteal:
            return false
        }
    }
}
