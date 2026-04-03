import Foundation

/// Computed at runtime from Roster + SleeperUser + League metadata.
/// Not Codable -- this is a view model assembled from API data.
struct StandingsTeam: Identifiable, Sendable {
    let rosterId: Int
    let userId: String
    let username: String
    let displayName: String
    let teamName: String
    let avatarId: String?
    let division: Int
    let divisionName: String
    let divisionAvatar: String?
    let wins: Int
    let losses: Int
    let ties: Int
    let fpts: Double
    let fptsAgainst: Double
    let streak: Streak
    var leagueRank: Int
    var divisionRank: Int

    var id: Int { rosterId }

    // MARK: - Computed

    var record: String {
        if ties > 0 {
            return "\(wins)-\(losses)-\(ties)"
        }
        return "\(wins)-\(losses)"
    }

    var winPct: Double {
        let games = wins + losses + ties
        guard games > 0 else { return 0 }
        return Double(wins) / Double(games)
    }

    var pointsDiff: Double {
        fpts - fptsAgainst
    }

    var pointsPerGame: Double {
        let games = wins + losses + ties
        guard games > 0 else { return 0 }
        return fpts / Double(games)
    }

    var avatarURL: URL? {
        avatarId.flatMap { URL(string: "https://sleepercdn.com/avatars/\($0)") }
    }

    var hasDivision: Bool {
        !divisionName.isEmpty && divisionName != "Unknown Division"
    }
}

// MARK: - Streak

struct Streak: Sendable {
    enum StreakType: String, Sendable {
        case win
        case loss
        case none = ""
    }

    let type: StreakType
    let total: Int

    static let none = Streak(type: .none, total: 0)

    var displayString: String {
        guard total > 0 else { return "-" }
        switch type {
        case .win: return "W\(total)"
        case .loss: return "L\(total)"
        case .none: return "-"
        }
    }
}
