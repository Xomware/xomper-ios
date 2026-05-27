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

    /// Mock-draft reports — one per personality (`bpa`, `team-fit`,
    /// `wildcard`). Populated by `loadMockDrafts()`. Held separately
    /// from `archive` so `MocksView` can render them without scanning
    /// the full archive on every render, and so the mock-draft surface
    /// can refresh independently of the main archive list.
    private(set) var mockDrafts: [AIReport] = []
    private(set) var isLoadingMockDrafts = false
    private(set) var mockDraftsError: Error?
    private(set) var mockDraftsLoadedAt: Date?

    /// Weekly recap reports indexed by `period` (e.g. `"2025W04"`).
    /// Populated by `loadWeeklyReport(period:)` and consumed by
    /// `MatchupsView` to render per-matchup blurbs under the matchup
    /// cards. Cached so flipping between weeks doesn't re-fetch.
    private(set) var weeklyReportsByPeriod: [String: AIReport] = [:]
    private(set) var loadingWeeklyPeriods: Set<String> = []

    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: Error?
    private(set) var lastLoadedAt: Date?

    /// Admin-only opt-in to see redacted rows in the archive. Defaults
    /// off so admins see the same view as everyone else by default. The
    /// archive view gates the toolbar toggle behind `authStore.isAdmin`,
    /// and the server already filters redacted rows for non-admin
    /// callers — this flag is only meaningful when the caller is admin.
    /// Client-side filter is defense-in-depth on top of the server.
    var showRedacted: Bool = false

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

    /// Fetch every mock-draft report (one per personality) for the
    /// active league. Replaces `mockDrafts` wholesale on success.
    /// Skips re-fetch within 12 hours unless `force` is set.
    ///
    /// Loaded lazily by `MocksView` on first appearance and re-fetched
    /// by pull-to-refresh.
    func loadMockDrafts(force: Bool = false) async {
        guard !isLoadingMockDrafts else { return }
        if !force,
           !mockDrafts.isEmpty,
           let last = mockDraftsLoadedAt,
           Date().timeIntervalSince(last) < 12 * 60 * 60 {
            return
        }
        isLoadingMockDrafts = true
        defer { isLoadingMockDrafts = false }
        mockDraftsError = nil

        do {
            let rows = try await apiClient.fetchMockDrafts()
            self.mockDrafts = rows
            self.mockDraftsLoadedAt = Date()
        } catch {
            self.mockDraftsError = error
        }
    }

    /// Fetch the weekly recap whose `period` matches the supplied
    /// string (e.g. `"2025W04"`). Cached in `weeklyReportsByPeriod`
    /// so subsequent reads on the same week return immediately. No-op
    /// when the period is already cached or in-flight.
    ///
    /// Called from `MatchupsView` when the user expands a past,
    /// scored week so the per-matchup blurbs can render inline.
    func loadWeeklyReport(period: String, force: Bool = false) async {
        guard !period.isEmpty else { return }
        if !force,
           weeklyReportsByPeriod[period] != nil {
            return
        }
        guard !loadingWeeklyPeriods.contains(period) else { return }
        loadingWeeklyPeriods.insert(period)
        defer { loadingWeeklyPeriods.remove(period) }

        do {
            if let report = try await apiClient.fetchAIReportByPeriod(
                type: .weekly,
                period: period
            ) {
                weeklyReportsByPeriod[period] = report
            }
            // `nil` is a valid "no recap for this week yet" answer —
            // leave the dictionary untouched so callers can fall back
            // to the no-blurb empty state.
        } catch {
            self.error = error
        }
    }

    // MARK: - F3 Report Flags

    /// Toggle `is_redacted` / `do_not_broadcast` on a single archive
    /// row. On API success, the matching row in `archive` (and
    /// `latestByType` when present) is replaced with a fresh copy that
    /// carries the updated metadata so the UI reflects the new state
    /// instantly — no follow-up `/ai-reports/list` round-trip.
    ///
    /// Mirrors `AdminStore.setReportFlag` but mutates archive entries
    /// instead of triggering a `*Latest` re-fetch. Both stores route
    /// through the same `XomperAPIClientProtocol.setReportFlag` call.
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
        // Rebuild the report with the backend's authoritative metadata
        // map so any other metadata keys (broadcast_at, model, etc.)
        // round-trip cleanly. Then apply the mutation in place.
        let updated = AIReport(
            id: report.id,
            leagueId: report.leagueId,
            reportType: report.reportType,
            period: report.period,
            bodyMarkdown: report.bodyMarkdown,
            metadata: response.metadata,
            metadataRawJSON: nil,
            createdAt: report.createdAt,
            model: report.model,
            promptVersion: report.promptVersion
        )
        if let idx = archive.firstIndex(where: { $0.id == report.id }) {
            archive[idx] = updated
        }
        if latestByType[report.reportType]?.id == report.id {
            latestByType[report.reportType] = updated
        }
        return response.metadata
    }

    /// Format a `(season, week)` pair into the wire period string the
    /// backend stamps on weekly reports — e.g. `("2025", 4)` →
    /// `"2025W04"`. Centralized here so the view doesn't have to know
    /// the wire format.
    static func weeklyPeriod(season: String, week: Int) -> String {
        guard !season.isEmpty, week > 0 else { return "" }
        return String(format: "%@W%02d", season, week)
    }

    /// Clear all state and force a full reload — used by
    /// pull-to-refresh.
    func refresh() async {
        archive = []
        archiveCursor = nil
        latestByType = [:]
        mockDrafts = []
        mockDraftsLoadedAt = nil
        weeklyReportsByPeriod = [:]
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
