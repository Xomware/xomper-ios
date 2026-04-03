import Foundation

struct Draft: Codable, Identifiable, Sendable {
    let draftId: String
    let leagueId: String
    let type: String?
    let status: String?
    let startTime: Int?
    let sport: String?
    let settings: DraftSettings?
    let seasonType: String?
    let season: String
    let metadata: DraftMetadata?
    let lastPicked: Int?
    let lastMessageTime: Int?
    let lastMessageId: String?
    let draftOrder: [String: Int]?
    let creators: [String]?
    let created: Int?

    var id: String { draftId }

    enum CodingKeys: String, CodingKey {
        case draftId = "draft_id"
        case leagueId = "league_id"
        case type
        case status
        case startTime = "start_time"
        case sport
        case settings
        case seasonType = "season_type"
        case season
        case metadata
        case lastPicked = "last_picked"
        case lastMessageTime = "last_message_time"
        case lastMessageId = "last_message_id"
        case draftOrder = "draft_order"
        case creators
        case created
    }
}

// MARK: - DraftSettings

struct DraftSettings: Codable, Sendable {
    let teams: Int?
    let slotsWr: Int?
    let slotsTe: Int?
    let slotsRb: Int?
    let slotsQb: Int?
    let slotsK: Int?
    let slotsFlex: Int?
    let slotsDef: Int?
    let slotsBn: Int?
    let rounds: Int?
    let pickTimer: Int?

    enum CodingKeys: String, CodingKey {
        case teams
        case slotsWr = "slots_wr"
        case slotsTe = "slots_te"
        case slotsRb = "slots_rb"
        case slotsQb = "slots_qb"
        case slotsK = "slots_k"
        case slotsFlex = "slots_flex"
        case slotsDef = "slots_def"
        case slotsBn = "slots_bn"
        case rounds
        case pickTimer = "pick_timer"
    }
}

// MARK: - DraftMetadata

struct DraftMetadata: Codable, Sendable {
    let scoringType: String?
    let name: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case scoringType = "scoring_type"
        case name
        case description
    }
}

// MARK: - DraftPick

struct DraftPick: Codable, Identifiable, Sendable {
    let playerId: String
    let pickedBy: String?
    let rosterId: String?
    let round: Int
    let draftSlot: Int
    let pickNo: Int
    let metadata: DraftPickMetadata?
    let isKeeper: Bool?
    let draftId: String?

    var id: String { "\(draftId ?? "unknown")-\(pickNo)" }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case pickedBy = "picked_by"
        case rosterId = "roster_id"
        case round
        case draftSlot = "draft_slot"
        case pickNo = "pick_no"
        case metadata
        case isKeeper = "is_keeper"
        case draftId = "draft_id"
    }
}

// MARK: - DraftPickMetadata

struct DraftPickMetadata: Codable, Sendable {
    let team: String?
    let status: String?
    let sport: String?
    let position: String?
    let playerId: String?
    let number: String?
    let newsUpdated: String?
    let lastName: String?
    let injuryStatus: String?
    let firstName: String?

    enum CodingKeys: String, CodingKey {
        case team
        case status
        case sport
        case position
        case playerId = "player_id"
        case number
        case newsUpdated = "news_updated"
        case lastName = "last_name"
        case injuryStatus = "injury_status"
        case firstName = "first_name"
    }
}
