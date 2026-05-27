import Foundation

/// Drives the Admin → Test Email sub-screen (F1).
///
/// Owns:
/// - `recipients` — the whitelisted-user list pulled from
///   `GET /admin/email-test-recipients` for the picker.
/// - `selectedRecipient` / `selectedReport` — the two picker
///   bindings; both must be non-nil before the Send button enables.
/// - `isSending` — flips while a `POST /admin/email-test` is in
///   flight. Disables the button + shows a spinner.
/// - `lastResult` — last successful response. Surfaces the "✓ Sent
///   to <email> at <time>" toast.
/// - `lastError` — last error from a send. Surfaces a red error toast.
/// - `recentSends` — last N rows from
///   `/admin/notifications?kind=email` client-side filtered to
///   `template == "ai_review_test"`. Renders the receipts list at the
///   bottom of the screen.
///
/// All API calls go through the shared `XomperAPIClient`; tests
/// substitute a `XomperAPIClientProtocol` mock via the init.
@Observable
@MainActor
final class TestEmailStore {

    // MARK: - State

    private(set) var recipients: [TestEmailRecipient] = []
    private(set) var isLoadingRecipients = false
    private(set) var recipientsError: String?

    /// Two-way bound by the recipient picker. `nil` until the admin
    /// taps a row.
    var selectedRecipient: TestEmailRecipient?

    /// Two-way bound by the report picker. `nil` until the admin
    /// taps a row.
    var selectedReport: AIReport?

    private(set) var isSending = false
    private(set) var lastResult: TestEmailResponse?
    private(set) var lastError: String?

    /// Receipts list — last few notification-log rows whose template
    /// is `ai_review_test`. Newest-first by `epoch_ms`.
    private(set) var recentSends: [AdminNotificationLogEntry] = []
    private(set) var isLoadingRecentSends = false

    // MARK: - Dependencies

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Loaders

    /// Fetch the whitelisted recipient list. Replaces `recipients`
    /// wholesale on success. Surfaces error to `recipientsError`
    /// on failure (caller renders inline; doesn't crash the view).
    func loadRecipients() async {
        guard !isLoadingRecipients else { return }
        isLoadingRecipients = true
        recipientsError = nil
        defer { isLoadingRecipients = false }

        do {
            recipients = try await apiClient.fetchTestEmailRecipients()
        } catch {
            recipientsError = error.localizedDescription
        }
    }

    /// Fetch the last N email send attempts and post-filter for the
    /// `ai_review_test` template. Backend `notification_log` rows
    /// don't yet expose `template` as a query param, so we pull a
    /// wider window and filter client-side.
    ///
    /// `sleeperUserId` is the *caller's* id — `adminListNotifications`
    /// gates on admin server-side but requires the caller id as a
    /// query param to scope its read.
    func loadRecentSends(sleeperUserId: String) async {
        guard !sleeperUserId.isEmpty else { return }
        guard !isLoadingRecentSends else { return }
        isLoadingRecentSends = true
        defer { isLoadingRecentSends = false }

        do {
            let response = try await apiClient.adminListNotifications(
                sleeperUserId: sleeperUserId,
                daysBack: 7,
                kind: "email",
                status: nil,
                limit: 50
            )
            // Server doesn't yet expose `template` in row payloads;
            // body_snippet / subject can vary so we can't safely
            // post-filter here. For V1 we surface every email send
            // and let the receipts list act as a general feed.
            // Once the backend persists `template` on rows + returns
            // it, this filter tightens to template == "ai_review_test".
            recentSends = response.rows
        } catch {
            // Silent — the receipts list is best-effort; lastError
            // is reserved for failed *sends* which are the primary
            // surface on this screen.
        }
    }

    // MARK: - Send

    /// Send the currently-selected report to the currently-selected
    /// recipient. No-op when either picker is nil. On success, stores
    /// the response in `lastResult` and refreshes the receipts list
    /// so the row appears under the button.
    func sendTest(sleeperUserId: String) async {
        guard let recipient = selectedRecipient else { return }
        guard let report = selectedReport else { return }

        await sendTest(
            report: report,
            recipient: recipient,
            sleeperUserId: sleeperUserId
        )
    }

    /// Explicit-args overload used by tests and any future call site
    /// that wants to bypass the picker bindings. Keeps the single
    /// source of truth for the actual API + state flow.
    func sendTest(
        report: AIReport,
        recipient: TestEmailRecipient,
        sleeperUserId: String
    ) async {
        guard !isSending else { return }
        isSending = true
        lastError = nil
        lastResult = nil
        defer { isSending = false }

        do {
            let response = try await apiClient.sendTestEmail(
                recipientSleeperUserId: recipient.userId,
                reportId: report.id
            )
            lastResult = response
            // Refresh the receipts list so the new send appears.
            if !sleeperUserId.isEmpty {
                await loadRecentSends(sleeperUserId: sleeperUserId)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Clear toast/result state — call when navigating away or
    /// before kicking off a fresh send.
    func reset() {
        lastResult = nil
        lastError = nil
    }
}
