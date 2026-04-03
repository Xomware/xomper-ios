import Foundation

struct MatchupHistoryRecord: Codable, Identifiable, Sendable {
    let leagueId: String
    let season: String
    let week: Int
    let matchupId: Int
    let teamARosterId: Int
    let teamAUserId: String
    let teamAUsername: String
    let teamATeamName: String
    let teamAPoints: Double
    let teamBRosterId: Int
    let teamBUserId: String
    let teamBUsername: String
    let teamBTeamName: String
    let teamBPoints: Double
    let winnerRosterId: Int?
    let isPlayoff: Bool
    let isChampionship: Bool
    let teamADivision: Int
    let teamBDivision: Int

    var id: String { "\(leagueId)-\(season)-\(week)-\(matchupId)" }

    enum CodingKeys: String, CodingKey {
        case leagueId = "league_id"
        case season
        case week
        case matchupId = "matchup_id"
        case teamARosterId = "team_a_roster_id"
        case teamAUserId = "team_a_user_id"
        case teamAUsername = "team_a_username"
        case teamATeamName = "team_a_team_name"
        case teamAPoints = "team_a_points"
        case teamBRosterId = "team_b_roster_id"
        case teamBUserId = "team_b_user_id"
        case teamBUsername = "team_b_username"
        case teamBTeamName = "team_b_team_name"
        case teamBPoints = "team_b_points"
        case winnerRosterId = "winner_roster_id"
        case isPlayoff = "is_playoff"
        case isChampionship = "is_championship"
        case teamADivision = "team_a_division"
        case teamBDivision = "team_b_division"
    }
}
