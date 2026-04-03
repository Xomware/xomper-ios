import Foundation

struct NflState: Codable, Sendable {
    let week: Int
    let season: String
    let seasonType: String
    let seasonStartDate: String?
    let previousSeason: String?
    let leg: Int
    let leagueSeason: String?
    let leagueCreateSeason: String?
    let displayWeek: Int

    enum CodingKeys: String, CodingKey {
        case week
        case season
        case seasonType = "season_type"
        case seasonStartDate = "season_start_date"
        case previousSeason = "previous_season"
        case leg
        case leagueSeason = "league_season"
        case leagueCreateSeason = "league_create_season"
        case displayWeek = "display_week"
    }

    // MARK: - Computed

    var isRegularSeason: Bool {
        seasonType == "regular"
    }

    var displayLabel: String {
        "Week \(displayWeek) - \(seasonType.uppercased()) Season"
    }
}
