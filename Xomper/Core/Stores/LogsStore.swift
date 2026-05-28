import Foundation

/// Drives the Admin → Logs sub-screen (F5).
///
/// Owns the picker selections (log group, level filter, search text)
/// plus the paginated event list, the next-token cursor, and a
/// client-side 5s rate limit on refreshes. Pagination ("Load older")
/// deliberately bypasses the rate limit — that gate is for "refresh"
/// affordances (pull-to-refresh + manual toolbar refresh), not for
/// user-initiated next-page taps.
///
/// All API calls go through the shared `XomperAPIClient`; tests
/// substitute a `XomperAPIClientProtocol` mock via the init.
@Observable
@MainActor
final class LogsStore {

    // MARK: - State

    private(set) var events: [LogEvent] = []
    private(set) var nextToken: String?

    /// Sensible default — most active log group across the season.
    var selectedLogGroup: LogGroup = .aiReviewWeekly

    /// Nil = "All" — backend omits the level filter from the
    /// CloudWatch `filterPattern`.
    var levelFilter: LogLevel?

    /// Free-text search. Empty string = no search filter; the API
    /// helper drops empty values from the query.
    var searchText: String = ""

    private(set) var isLoading: Bool = false
    private(set) var error: String?

    /// Stamped at the start of each successful (or attempted)
    /// `loadEvents` call. Used to enforce the 5s minimum between
    /// refreshes — pagination via `loadMore` does NOT touch this.
    private(set) var lastFetchAt: Date?

    /// Flipped true for ~2s when a refresh is blocked by the
    /// rate-limit gate, so the view can render a transient banner.
    private(set) var throttled: Bool = false

    // MARK: - Constants

    /// Minimum gap between two `loadEvents` calls. Hard-coded per F5
    /// plan Q5 — tuneable if it proves annoying in practice.
    private let rateLimitSeconds: TimeInterval = 5

    // MARK: - Dependencies

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Loaders

    /// Fetch the first page of events for the current filter
    /// combination. Resets `events` + `nextToken` on success.
    ///
    /// Enforces the 5s client-side rate limit by comparing
    /// `Date.now` to `lastFetchAt`. When blocked, sets `throttled =
    /// true` for ~2s so the view can flash a "Hold on a sec…"
    /// banner, then no-ops.
    func loadEvents() async {
        guard !isLoading else { return }

        if let last = lastFetchAt,
           Date().timeIntervalSince(last) < rateLimitSeconds {
            throttled = true
            // Auto-clear the throttle banner after a couple seconds
            // so it's transient. Skip in test environments where
            // mock clocks would race with the real-time delay.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.clearThrottleFlag()
            }
            return
        }

        isLoading = true
        error = nil
        throttled = false
        lastFetchAt = Date()
        defer { isLoading = false }

        do {
            let response = try await apiClient.fetchLogEvents(
                logGroup: selectedLogGroup,
                level: levelFilter,
                search: searchText.isEmpty ? nil : searchText,
                limit: 50,
                cursor: nil
            )
            events = response.events
            nextToken = response.nextToken
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Append the next page of events via `nextToken`. No-op when
    /// no token is available or a load is already in flight.
    /// Deliberately bypasses the 5s rate limit — pagination is a
    /// user-initiated action and shouldn't be throttled.
    func loadMore() async {
        guard !isLoading else { return }
        guard let cursor = nextToken, !cursor.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.fetchLogEvents(
                logGroup: selectedLogGroup,
                level: levelFilter,
                search: searchText.isEmpty ? nil : searchText,
                limit: 50,
                cursor: cursor
            )
            // Defensive dedup — CloudWatch eventId is normally
            // unique across pages, but a misbehaving cursor cycle
            // would crash the SwiftUI list with duplicate IDs.
            let existingIds = Set(events.map(\.id))
            let appended = response.events.filter { !existingIds.contains($0.id) }
            events.append(contentsOf: appended)
            nextToken = response.nextToken
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Reset filters to defaults. Does NOT trigger a fetch — the
    /// view chains `await loadEvents()` after if desired.
    func resetFilters() {
        searchText = ""
        levelFilter = nil
        selectedLogGroup = .aiReviewWeekly
    }

    /// Replace the selected log group + immediately reload. Resets
    /// the events list because cross-group ids share no namespace.
    func setLogGroup(_ group: LogGroup) async {
        selectedLogGroup = group
        // Clear the rate-limit timestamp so the immediate post-pick
        // fetch isn't throttled — switching groups is a user action,
        // not a refresh.
        lastFetchAt = nil
        await loadEvents()
    }

    /// Replace the level filter + immediately reload.
    func setLevel(_ level: LogLevel?) async {
        levelFilter = level
        lastFetchAt = nil
        await loadEvents()
    }

    /// Clear the in-memory state. Used when navigating away from
    /// the sub-screen so the next visit starts fresh.
    func reset() {
        events = []
        nextToken = nil
        error = nil
        lastFetchAt = nil
        throttled = false
    }

    // MARK: - Private

    private func clearThrottleFlag() {
        throttled = false
    }
}
