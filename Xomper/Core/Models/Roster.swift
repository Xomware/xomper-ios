import Foundation

struct Roster: Codable, Identifiable, Sendable {
    let rosterId: Int
    let ownerId: String?
    let leagueId: String
    let players: [String]?
    let starters: [String]?
    let reserve: [String]?
    let taxi: [String]?
    let coOwners: [String]?
    let keepers: [String]?
    let settings: RosterSettings
    let metadata: [String: AnyCodableValue]?
    let playerMap: [String: AnyCodableValue]?

    var id: Int { rosterId }

    enum CodingKeys: String, CodingKey {
        case rosterId = "roster_id"
        case ownerId = "owner_id"
        case leagueId = "league_id"
        case players
        case starters
        case reserve
        case taxi
        case coOwners = "co_owners"
        case keepers
        case settings
        case metadata
        case playerMap = "player_map"
    }

    // MARK: - Computed

    var pointsFor: Double {
        Double(settings.fpts) + Double(settings.fptsDecimal) / 100.0
    }

    var pointsAgainst: Double {
        Double(settings.fptsAgainst) + Double(settings.fptsAgainstDecimal) / 100.0
    }

    var record: String {
        if settings.ties > 0 {
            return "\(settings.wins)-\(settings.losses)-\(settings.ties)"
        }
        return "\(settings.wins)-\(settings.losses)"
    }

    var division: Int {
        settings.division
    }
}

// MARK: - RosterSettings

struct RosterSettings: Codable, Sendable {
    let wins: Int
    let losses: Int
    let ties: Int
    let division: Int
    let fpts: Int
    let fptsDecimal: Int
    let fptsAgainst: Int
    let fptsAgainstDecimal: Int
    let waiverPosition: Int?
    let waiverBudgetUsed: Int?
    let totalMoves: Int?

    enum CodingKeys: String, CodingKey {
        case wins
        case losses
        case ties
        case division
        case fpts
        case fptsDecimal = "fpts_decimal"
        case fptsAgainst = "fpts_against"
        case fptsAgainstDecimal = "fpts_against_decimal"
        case waiverPosition = "waiver_position"
        case waiverBudgetUsed = "waiver_budget_used"
        case totalMoves = "total_moves"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wins = (try? container.decode(Int.self, forKey: .wins)) ?? 0
        losses = (try? container.decode(Int.self, forKey: .losses)) ?? 0
        ties = (try? container.decode(Int.self, forKey: .ties)) ?? 0
        division = (try? container.decode(Int.self, forKey: .division)) ?? 0
        fpts = (try? container.decode(Int.self, forKey: .fpts)) ?? 0
        fptsDecimal = (try? container.decode(Int.self, forKey: .fptsDecimal)) ?? 0
        fptsAgainst = (try? container.decode(Int.self, forKey: .fptsAgainst)) ?? 0
        fptsAgainstDecimal = (try? container.decode(Int.self, forKey: .fptsAgainstDecimal)) ?? 0
        waiverPosition = try container.decodeIfPresent(Int.self, forKey: .waiverPosition)
        waiverBudgetUsed = try container.decodeIfPresent(Int.self, forKey: .waiverBudgetUsed)
        totalMoves = try container.decodeIfPresent(Int.self, forKey: .totalMoves)
    }
}
