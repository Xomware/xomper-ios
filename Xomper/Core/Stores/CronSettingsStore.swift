import Foundation

/// Drives the Admin → Cron Settings sub-screen.
///
/// One store per sub-screen — kept separate from `AdminTablesStore`
/// because cron settings have their own lifecycle (loaded on push,
/// not bootstrap-cached) and a different write pattern (per-row
/// optimistic toggle vs. F4's typed diff form). Splitting also
/// avoids polluting the F4 store with cron-specific state.
///
/// Optimistic updates: flipping a toggle mutates `settings` in place
/// immediately so the UI feels instantaneous, then fires the POST.
/// On failure we revert the row to its prior shape and surface the
/// error via `lastError`. Per-row spinner state lives in
/// `pendingKeys` so the row can show a small `ProgressView` while
/// the POST is in flight without blocking the rest of the list.
///
/// All API calls go through `XomperAPIClientProtocol`; tests
/// substitute a mock via the init.
@Observable
@MainActor
final class CronSettingsStore {

    // MARK: - State

    private(set) var settings: [CronSetting] = []
    private(set) var tableMissing: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var error: String?

    /// Per-row in-flight tracker. The set holds the `cronKey` of any
    /// row whose toggle is currently mid-POST. Used both for spinner
    /// visibility and for deduplication — a second toggle-tap on the
    /// same row while a save is in flight is dropped.
    private(set) var pendingKeys: Set<String> = []

    /// Last write error surfaced to the view. Cleared at the start of
    /// the next write. Distinct from `error` (load failure) so the
    /// list can keep rendering after a toggle fails.
    private(set) var lastError: String?

    // MARK: - Dependencies

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Load

    /// Fetch the cron settings list. Replaces `settings` wholesale on
    /// success. Surfaces error to `error` on failure (keeping any
    /// previously-loaded settings on screen so a transient network
    /// blip doesn't blank the list).
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.fetchCronSettings()
            settings = response.rows
            tableMissing = response.tableMissing
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Toggle

    /// Flip the `enabled` flag on one row. Optimistic — the row's
    /// state flips immediately, then the POST fires. On error the
    /// row is reverted and `lastError` is populated.
    ///
    /// Deduplicates: a second tap on the same row while the first
    /// POST is in flight is dropped.
    func toggleEnabled(cronKey: String, enabled: Bool) async {
        guard !pendingKeys.contains(cronKey) else { return }
        guard let idx = settings.firstIndex(where: { $0.cronKey == cronKey }) else { return }

        let original = settings[idx]
        // Optimistic flip.
        settings[idx] = original.with(enabled: enabled)
        pendingKeys.insert(cronKey)
        lastError = nil
        defer { pendingKeys.remove(cronKey) }

        do {
            let response = try await apiClient.updateCronSetting(
                cronKey: cronKey,
                enabled: enabled,
                testMode: nil
            )
            // Reconcile with server truth. If the server-resolved state
            // differs from our optimistic flip (e.g. concurrent edit),
            // the server value wins.
            if let confirmIdx = settings.firstIndex(where: { $0.cronKey == cronKey }) {
                let current = settings[confirmIdx]
                settings[confirmIdx] = CronSetting(
                    cronKey: response.cronKey,
                    enabled: response.enabled,
                    testMode: response.testMode,
                    description: current.description,
                    updatedAt: Date()
                )
            }
        } catch {
            // Revert the optimistic mutation. Look up the row again
            // because settings may have been replaced in between.
            if let revertIdx = settings.firstIndex(where: { $0.cronKey == cronKey }) {
                settings[revertIdx] = original
            }
            lastError = error.localizedDescription
        }
    }

    /// Flip the `test_mode` flag on one row. Same shape as
    /// `toggleEnabled` — optimistic mutation, server reconciliation,
    /// revert on failure.
    func toggleTestMode(cronKey: String, testMode: Bool) async {
        guard !pendingKeys.contains(cronKey) else { return }
        guard let idx = settings.firstIndex(where: { $0.cronKey == cronKey }) else { return }

        let original = settings[idx]
        settings[idx] = original.with(testMode: testMode)
        pendingKeys.insert(cronKey)
        lastError = nil
        defer { pendingKeys.remove(cronKey) }

        do {
            let response = try await apiClient.updateCronSetting(
                cronKey: cronKey,
                enabled: nil,
                testMode: testMode
            )
            if let confirmIdx = settings.firstIndex(where: { $0.cronKey == cronKey }) {
                let current = settings[confirmIdx]
                settings[confirmIdx] = CronSetting(
                    cronKey: response.cronKey,
                    enabled: response.enabled,
                    testMode: response.testMode,
                    description: current.description,
                    updatedAt: Date()
                )
            }
        } catch {
            if let revertIdx = settings.firstIndex(where: { $0.cronKey == cronKey }) {
                settings[revertIdx] = original
            }
            lastError = error.localizedDescription
        }
    }

    // MARK: - Derived

    /// True when any row has `test_mode == true`. Drives the
    /// "Test mode active" banner at the top of `CronSettingsView` —
    /// the recommendation from the plan's open-question section to
    /// surface a forgot-to-flip-back warning prominently.
    var anyTestModeActive: Bool {
        settings.contains(where: { $0.testMode })
    }
}
