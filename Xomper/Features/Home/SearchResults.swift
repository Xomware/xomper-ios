import Foundation

/// Aggregated search result payload populated by `SearchStore`.
///
/// V1 only ever populates one of the three buckets at a time (the bucket
/// matching the active `SearchMode`). The grouped shape exists so a future
/// "search-all" mode can populate multiple buckets without rewiring the
/// rendering layer.
struct SearchResults: Sendable {
    var user: SleeperUser?
    var league: League?
    var players: [Player]

    /// True when no bucket has any content. Used by the rendering layer to
    /// fall through to the global "no results" empty state.
    var isEmpty: Bool {
        user == nil && league == nil && players.isEmpty
    }

    static let empty = SearchResults(user: nil, league: nil, players: [])
}
