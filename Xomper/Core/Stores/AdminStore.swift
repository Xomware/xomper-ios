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

    // MARK: - Preseason AI Review state

    /// Latest preseason AI Review row from `/ai-reports/latest`.
    /// Drives the trigger card's status line + button label.
    /// `nil` until `loadPreseasonLatest()` runs (or if it errors).
    private(set) var preseasonLatest: AIReport?
    /// True while a trigger request is in flight. Disables the
    /// button and shows a spinner.
    private(set) var isTriggeringPreseason = false
    /// Last error from the trigger flow. Cleared on next trigger.
    private(set) var preseasonError: Error?
    /// Last successful trigger response. Surfaces delivery count +
    /// model in the result line.
    private(set) var preseasonResult: AIReviewTriggerResponse?

    /// Two-way bound by the AdminView toggle. Defaults to true so
    /// the first run is always dry-run for tone calibration.
    var preseasonDryRun: Bool = true

    // MARK: - Weekly AI Review state

    /// Latest weekly AI Review row from `/ai-reports/latest`.
    /// Drives the trigger card's status line + button label.
    /// `nil` until `loadWeeklyLatest()` runs (or if it errors).
    private(set) var weeklyLatest: AIReport?
    /// True while a trigger request is in flight. Disables the
    /// button and shows a spinner.
    private(set) var isTriggeringWeekly = false
    /// Last error from the trigger flow. Cleared on next trigger.
    private(set) var weeklyError: Error?
    /// Last successful trigger response. Surfaces delivery count +
    /// model in the result line.
    private(set) var weeklyResult: AIReviewTriggerResponse?

    /// Two-way bound by the AdminView toggle. Defaults to true so
    /// the first run is always dry-run for tone calibration.
    var weeklyDryRun: Bool = true

    /// Optional admin override. When non-nil the trigger request
    /// includes an explicit `week` field; when nil the backend
    /// resolves the just-completed week from `nfl_state.week - 1`.
    /// Driven by the override toggle + stepper on the weekly card.
    var weeklyWeekOverride: Int?

    // MARK: - F2 Email Previews

    /// In-memory store of rendered email previews per report type.
    /// Populated after each successful dry-run trigger (when the
    /// backend includes `previews` in the response). Broadcast
    /// responses do NOT touch this — pre-broadcast previews remain
    /// visible after a broadcast completes so the admin can compare.
    /// Cleared on app restart (per F2 plan Q3 — no persistence).
    private(set) var lastPreviewsByType: [AIReportType: [EmailPreview]] = [:]

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
            // F2: capture rendered previews from the dry-run response.
            // Broadcast responses leave `previews == nil`; we don't
            // overwrite in that case so the admin can still see what
            // was about to go out.
            if let previews = response.previews {
                lastPreviewsByType[.postDraft] = previews
            }
            // Refresh latest so the card label updates from "Generate"
            // to "Regenerate (force)" on next render.
            await loadPostDraftLatest()
            return response
        } catch {
            postDraftError = error
            throw error
        }
    }

    // MARK: - Preseason AI Review

    /// Reads the latest preseason report so the trigger card can
    /// reflect whether a dry-run / broadcast already happened. Silent
    /// on failure — the card just defaults to "no report yet" copy.
    func loadPreseasonLatest() async {
        do {
            preseasonLatest = try await apiClient.fetchLatestAIReport(type: .preseason)
        } catch {
            preseasonLatest = nil
        }
    }

    /// Fires the admin preseason trigger endpoint. Surfaces the
    /// response in `preseasonResult` on success or `preseasonError`
    /// on failure, and re-reads `preseasonLatest` afterwards so the
    /// card label reflects the new state.
    ///
    /// Throws so callers can decide whether to surface the error
    /// further (e.g. for confirmation dialogs). Internal state is
    /// updated regardless.
    @discardableResult
    func triggerPreseason(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse {
        isTriggeringPreseason = true
        preseasonError = nil
        preseasonResult = nil
        defer { isTriggeringPreseason = false }

        do {
            let response = try await apiClient.triggerPreseasonAIReview(
                dryRun: dryRun,
                force: force
            )
            preseasonResult = response
            // F2: see notes on the post-draft equivalent above.
            if let previews = response.previews {
                lastPreviewsByType[.preseason] = previews
            }
            // Refresh latest so the card label updates from "Generate"
            // to "Regenerate (force)" on next render.
            await loadPreseasonLatest()
            return response
        } catch {
            preseasonError = error
            throw error
        }
    }

    // MARK: - Weekly AI Review

    /// Reads the latest weekly report so the trigger card can reflect
    /// whether a dry-run / broadcast already happened for the most
    /// recent week. Silent on failure — the card just defaults to
    /// "no report yet" copy.
    func loadWeeklyLatest() async {
        do {
            weeklyLatest = try await apiClient.fetchLatestAIReport(type: .weekly)
        } catch {
            weeklyLatest = nil
        }
    }

    /// Fires the admin weekly trigger endpoint. Surfaces the response
    /// in `weeklyResult` on success or `weeklyError` on failure, and
    /// re-reads `weeklyLatest` afterwards so the card label reflects
    /// the new state.
    ///
    /// `week == nil` lets the backend resolve the just-completed week
    /// from Sleeper's `nfl_state`; the JSON key is omitted from the
    /// wire payload in that case (see `WeeklyTriggerRequest`).
    ///
    /// Throws so callers can decide whether to surface the error
    /// further. Internal state is updated regardless.
    @discardableResult
    func triggerWeekly(
        week: Int?,
        dryRun: Bool,
        force: Bool
    ) async throws -> AIReviewTriggerResponse {
        isTriggeringWeekly = true
        weeklyError = nil
        weeklyResult = nil
        defer { isTriggeringWeekly = false }

        do {
            let response = try await apiClient.triggerWeeklyAIReview(
                week: week,
                dryRun: dryRun,
                force: force
            )
            weeklyResult = response
            // F2: see notes on the post-draft equivalent above.
            if let previews = response.previews {
                lastPreviewsByType[.weekly] = previews
            }
            // Refresh latest so the card label updates from "Generate"
            // to "Regenerate (force)" on next render.
            await loadWeeklyLatest()
            return response
        } catch {
            weeklyError = error
            throw error
        }
    }

    // MARK: - F2 Previews

    /// Drops the in-memory preview set for one report type. Used by
    /// tests + by the preview view after a successful broadcast so
    /// stale previews don't linger past a successful send.
    func clearPreviews(for reportType: AIReportType) {
        lastPreviewsByType[reportType] = nil
    }

    // MARK: - F3 Report Flags

    /// Convenience accessor for the latest report of a given type.
    /// Used by `AIReviewPreviewView` to read the current DNB state
    /// for the active report type without switching on the type at
    /// the call site.
    func latest(for reportType: AIReportType) -> AIReport? {
        switch reportType {
        case .postDraft: return postDraftLatest
        case .preseason: return preseasonLatest
        case .weekly:    return weeklyLatest
        case .mock:      return nil
        }
    }

    /// Toggle a metadata flag (F3) on a report row. Calls the backend
    /// then re-fetches the affected `*Latest` so the trigger card +
    /// preview view both reflect the new state. Throws so the caller
    /// can surface the error inline (the preview view shows it in the
    /// existing `broadcastError` block).
    ///
    /// Returns the full updated metadata map for callers that want to
    /// apply it locally instead of re-fetching (the archive flow
    /// does this via `AIReviewStore.setReportFlag`).
    @discardableResult
    func setReportFlag(
        report: AIReport,
        flag: ReportFlag,
        value: Bool
    ) async throws -> [String: String] {
        let response = try await apiClient.setReportFlag(
            leagueId: report.leagueId,
            reportType: report.reportType,
            period: report.period,
            flag: flag,
            value: value
        )
        // Refresh the affected latest so trigger card + preview view
        // pick up the flag change without a manual re-fetch.
        switch report.reportType {
        case .postDraft: await loadPostDraftLatest()
        case .preseason: await loadPreseasonLatest()
        case .weekly:    await loadWeeklyLatest()
        case .mock:      break
        }
        return response.metadata
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
