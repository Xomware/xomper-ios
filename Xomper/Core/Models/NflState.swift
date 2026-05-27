import Foundation

struct NflState: Codable, Sendable {
    let week: Int
    let season: String
    let seasonType: String?
    let seasonStartDate: String?
    let previousSeason: String?
    let leg: Int?
    let leagueSeason: String?
    let leagueCreateSeason: String?
    let displayWeek: Int?

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

    var isPostseason: Bool {
        seasonType == "post"
    }

    /// True during regular season AND playoffs — i.e. any time
    /// fantasy standings are live and meaningful. Use this for the
    /// "show live standings vs offseason countdown" gate so that
    /// week-15-17 playoffs don't incorrectly flip the Standings view
    /// to the offseason empty state (F4 follow-up).
    var hasLiveStandings: Bool {
        isRegularSeason || isPostseason
    }

    var displayLabel: String {
        "Week \(displayWeek ?? week) - \(seasonType?.uppercased() ?? "OFF") Season"
    }
}
