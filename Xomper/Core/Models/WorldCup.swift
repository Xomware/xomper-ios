import Foundation

/// Computed at runtime from matchup history data.
/// Not Codable -- assembled from cross-season divisional matchup analysis.
struct WorldCupDivision: Identifiable, Sendable {
    let divisionNumber: Int
    let divisionName: String
    var teams: [WorldCupTeamRecord]

    var id: Int { divisionNumber }
}

struct WorldCupTeamRecord: Identifiable, Sendable {
    let userId: String
    let username: String
    let teamName: String
    let division: Int
    let divisionName: String
    var wins: Int
    var losses: Int
    var ties: Int
    var pointsFor: Double
    var pointsAgainst: Double
    var qualified: Bool
    var seasonBreakdown: [SeasonBreakdown]

    var id: String { userId }

    var record: String {
        if ties > 0 {
            return "\(wins)-\(losses)-\(ties)"
        }
        return "\(wins)-\(losses)"
    }

    var pointsDiff: Double {
        pointsFor - pointsAgainst
    }
}

struct SeasonBreakdown: Sendable {
    let season: String
    var wins: Int
    var losses: Int
    var pointsFor: Double
    var pointsAgainst: Double
}
