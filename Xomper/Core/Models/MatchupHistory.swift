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
    /// Final placement this matchup decided, taken from Sleeper's
    /// playoff bracket (`match.placement`). 1 = championship, 3 = 3rd
    /// place, 5/7/9/11 = consolation seeding rounds. `nil` for
    /// regular-season games and for early-round playoff games whose
    /// match doesn't carry a placement.
    let playoffPlacement: Int?

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
        case playoffPlacement = "playoff_placement"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leagueId = try c.decode(String.self, forKey: .leagueId)
        season = try c.decode(String.self, forKey: .season)
        week = try c.decode(Int.self, forKey: .week)
        matchupId = try c.decode(Int.self, forKey: .matchupId)
        teamARosterId = try c.decode(Int.self, forKey: .teamARosterId)
        teamAUserId = try c.decode(String.self, forKey: .teamAUserId)
        teamAUsername = try c.decode(String.self, forKey: .teamAUsername)
        teamATeamName = try c.decode(String.self, forKey: .teamATeamName)
        teamAPoints = try c.decode(Double.self, forKey: .teamAPoints)
        teamBRosterId = try c.decode(Int.self, forKey: .teamBRosterId)
        teamBUserId = try c.decode(String.self, forKey: .teamBUserId)
        teamBUsername = try c.decode(String.self, forKey: .teamBUsername)
        teamBTeamName = try c.decode(String.self, forKey: .teamBTeamName)
        teamBPoints = try c.decode(Double.self, forKey: .teamBPoints)
        winnerRosterId = try c.decodeIfPresent(Int.self, forKey: .winnerRosterId)
        isPlayoff = try c.decode(Bool.self, forKey: .isPlayoff)
        isChampionship = try c.decode(Bool.self, forKey: .isChampionship)
        teamADivision = try c.decode(Int.self, forKey: .teamADivision)
        teamBDivision = try c.decode(Int.self, forKey: .teamBDivision)
        playoffPlacement = try c.decodeIfPresent(Int.self, forKey: .playoffPlacement)
    }

    init(
        leagueId: String,
        season: String,
        week: Int,
        matchupId: Int,
        teamARosterId: Int,
        teamAUserId: String,
        teamAUsername: String,
        teamATeamName: String,
        teamAPoints: Double,
        teamBRosterId: Int,
        teamBUserId: String,
        teamBUsername: String,
        teamBTeamName: String,
        teamBPoints: Double,
        winnerRosterId: Int?,
        isPlayoff: Bool,
        isChampionship: Bool,
        teamADivision: Int,
        teamBDivision: Int,
        playoffPlacement: Int? = nil
    ) {
        self.leagueId = leagueId
        self.season = season
        self.week = week
        self.matchupId = matchupId
        self.teamARosterId = teamARosterId
        self.teamAUserId = teamAUserId
        self.teamAUsername = teamAUsername
        self.teamATeamName = teamATeamName
        self.teamAPoints = teamAPoints
        self.teamBRosterId = teamBRosterId
        self.teamBUserId = teamBUserId
        self.teamBUsername = teamBUsername
        self.teamBTeamName = teamBTeamName
        self.teamBPoints = teamBPoints
        self.winnerRosterId = winnerRosterId
        self.isPlayoff = isPlayoff
        self.isChampionship = isChampionship
        self.teamADivision = teamADivision
        self.teamBDivision = teamBDivision
        self.playoffPlacement = playoffPlacement
    }
}
