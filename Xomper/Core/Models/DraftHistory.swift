import Foundation

struct DraftHistoryRecord: Codable, Identifiable, Sendable {
    let leagueId: String
    let draftId: String
    let season: String
    let round: Int
    let pickNo: Int
    let draftSlot: Int
    let playerId: String
    let playerName: String
    let playerPosition: String
    let playerTeam: String
    let pickedByUserId: String
    let pickedByRosterId: Int
    let pickedByUsername: String
    let pickedByTeamName: String
    let isKeeper: Bool

    var id: String { "\(draftId)-\(pickNo)" }

    enum CodingKeys: String, CodingKey {
        case leagueId = "league_id"
        case draftId = "draft_id"
        case season
        case round
        case pickNo = "pick_no"
        case draftSlot = "draft_slot"
        case playerId = "player_id"
        case playerName = "player_name"
        case playerPosition = "player_position"
        case playerTeam = "player_team"
        case pickedByUserId = "picked_by_user_id"
        case pickedByRosterId = "picked_by_roster_id"
        case pickedByUsername = "picked_by_username"
        case pickedByTeamName = "picked_by_team_name"
        case isKeeper = "is_keeper"
    }
}
