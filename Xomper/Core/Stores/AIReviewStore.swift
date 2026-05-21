import Foundation

/// Drives the AI Review surfaces — Home banner, archive list, detail
/// view. One store instance is held by `MainShell` and shared across
/// all three views so a single fetch populates everything.
///
/// Data sources:
/// - `latestByType[.weekly]` etc. — latest-per-type, populated by
///   `loadLatest(type:)`. Home banner picks the most-recent across
///   the three types.
/// - `archive` — newest-first paginated list, populated by
///   `loadArchive()`. `loadMore()` advances the cursor.
///
/// Freshness: `loadLatest` short-circuits when a value is already in
/// the dictionary AND the store was fetched within the last 12 hours
/// — mirrors `PlayerValuesStore`. `force: true` bypasses.
@Observable
@MainActor
final class AIReviewStore {

    // MARK: - State

    /// Latest report keyed by type. Empty until first `loadLatest` lands.
    private(set) var latestByType: [AIReportType: AIReport] = [:]

    /// Newest-first archive list across all report types.
    private(set) var archive: [AIReport] = []

    /// Opaque pagination cursor for the next archive page.
    /// `nil` means no more pages.
    private(set) var archiveCursor: String?

    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: Error?
    private(set) var lastLoadedAt: Date?

    // MARK: - Dependencies

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Loaders

    /// Fetch the latest report for one type. Skips re-fetch within
    /// 12 hours unless `force` is set. Called from the Home card on
    /// appearance (in parallel for all three types).
    func loadLatest(type: AIReportType, force: Bool = false) async {
        if !force,
           latestByType[type] != nil,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < 12 * 60 * 60 {
            return
        }
        do {
            if let report = try await apiClient.fetchLatestAIReport(type: type) {
                latestByType[type] = report
            } else {
                // Backend returned null — explicitly clear so the UI
                // doesn't keep showing a stale value from before this
                // call. (No-op if it wasn't there.)
                latestByType.removeValue(forKey: type)
            }
            lastLoadedAt = Date()
        } catch {
            self.error = error
        }
    }

    /// Fetch the first page of the archive list. Replaces `archive`
    /// + resets `archiveCursor`. Skips when already loaded within 12
    /// hours unless `force` is set.
    func loadArchive(force: Bool = false) async {
        guard !isLoading else { return }
        if !force,
           !archive.isEmpty,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < 12 * 60 * 60 {
            return
        }
        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            let response = try await apiClient.fetchAIReportsList(
                type: nil,
                limit: 20,
                cursor: nil
            )
            self.archive = response.rows
            self.archiveCursor = response.nextCursor
            self.lastLoadedAt = Date()
        } catch {
            self.error = error
        }
    }

    /// Fetch the next page of the archive, appending to `archive`.
    /// No-ops when `archiveCursor` is nil (no more pages) or a load
    /// is already in flight.
    func loadMore() async {
        guard !isLoadingMore, !isLoading else { return }
        guard let cursor = archiveCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await apiClient.fetchAIReportsList(
                type: nil,
                limit: 20,
                cursor: cursor
            )
            // De-dupe by id in case the cursor returns overlap.
            let existing = Set(archive.map(\.id))
            let fresh = response.rows.filter { !existing.contains($0.id) }
            self.archive.append(contentsOf: fresh)
            self.archiveCursor = response.nextCursor
        } catch {
            self.error = error
        }
    }

    /// Clear all state and force a full reload — used by
    /// pull-to-refresh.
    func refresh() async {
        archive = []
        archiveCursor = nil
        latestByType = [:]
        lastLoadedAt = nil
        error = nil
        await loadArchive(force: true)
    }

    // MARK: - Convenience

    /// Most-recent report across all three types — the banner card
    /// renders this. `nil` when no reports exist yet.
    var mostRecentLatest: AIReport? {
        latestByType
            .values
            .max(by: { $0.createdAt < $1.createdAt })
    }
}
