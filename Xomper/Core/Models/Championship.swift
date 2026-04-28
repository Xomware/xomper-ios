import Foundation

/// Derived in-memory model representing a championship win for a single user
/// in a single season. Built from `MatchupHistoryRecord` — never serialized
/// to/from JSON, never persisted.
struct Championship: Identifiable, Sendable, Hashable {
    let season: String
    let leagueId: String
    let week: Int
    let teamName: String
    let pointsFor: Double
    let pointsAgainst: Double
    let opponentTeamName: String

    var id: String { "\(leagueId)-\(season)-\(week)" }
}
