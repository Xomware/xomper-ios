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
