import Foundation

struct Matchup: Codable, Sendable {
    let rosterId: Int
    let matchupId: Int?
    let players: [String]?
    let starters: [String]?
    let startersPoints: [Double]?
    let playersPoints: [String: Double]?
    let points: Double?
    let customPoints: Double?

    enum CodingKeys: String, CodingKey {
        case rosterId = "roster_id"
        case matchupId = "matchup_id"
        case players
        case starters
        case startersPoints = "starters_points"
        case playersPoints = "players_points"
        case points
        case customPoints = "custom_points"
    }

    var resolvedPoints: Double {
        points ?? 0
    }
}
