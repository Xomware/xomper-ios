import Foundation

/// All-time per-user stats derived from `MatchupHistoryRecord`. Pure
/// computation — never serialized, never persisted. Built by
/// `HistoryStore.careerStats(forUserId:)`.
struct CareerStats: Sendable, Hashable {
    let wins: Int
    let losses: Int
    let ties: Int
    let pointsFor: Double
    let pointsAgainst: Double
    let highestScore: Double
    let highestScoreWeek: WeekRef?
    let lowestScore: Double
    let lowestScoreWeek: WeekRef?
    let seasonsPlayed: Int
    let playoffAppearances: Int

    var totalGames: Int { wins + losses + ties }

    /// Win rate as a fraction in [0, 1]. Returns 0 when no games played.
    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames)
    }

    /// Average points per game played. Returns 0 when no games played.
    var averagePointsFor: Double {
        guard totalGames > 0 else { return 0 }
        return pointsFor / Double(totalGames)
    }

    static let empty = CareerStats(
        wins: 0, losses: 0, ties: 0,
        pointsFor: 0, pointsAgainst: 0,
        highestScore: 0, highestScoreWeek: nil,
        lowestScore: 0, lowestScoreWeek: nil,
        seasonsPlayed: 0, playoffAppearances: 0
    )

    var hasGames: Bool { totalGames > 0 }

    struct WeekRef: Sendable, Hashable {
        let season: String
        let week: Int
    }
}
