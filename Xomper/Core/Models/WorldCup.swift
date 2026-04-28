import Foundation

// MARK: - Clinch Status

/// Three-state qualification status for World Cup standings.
/// Computed by `ClinchCalculator`; replaces the old boolean `qualified` flag.
enum ClinchStatus: String, Sendable {
    /// Team has mathematically clinched a top-2 seed — no remaining opponent can catch them.
    case clinched
    /// Qualification is still undetermined.
    case alive
    /// Team cannot reach the 2nd-seed win total even by winning all remaining games.
    case eliminated
}

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
    var clinchStatus: ClinchStatus
    var seasonBreakdown: [SeasonBreakdown]

    var id: String { userId }

    /// Convenience: `true` only when the team has mathematically clinched a qualifying seat.
    var qualifiedForBracket: Bool { clinchStatus == .clinched }

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
