import Foundation

struct League: Codable, Identifiable, Sendable {
    let leagueId: String
    let name: String?
    let season: String
    let seasonType: String?
    let sport: String?
    let status: String?
    let totalRosters: Int?
    let shard: Int?
    let draftId: String?
    let previousLeagueId: String?
    let bracketId: String?
    let groupId: String?
    let avatar: String?
    let settings: LeagueSettings?
    let scoringSettings: [String: Double]?
    let rosterPositions: [String]?
    let metadata: [String: AnyCodableValue]?

    var id: String { leagueId }

    enum CodingKeys: String, CodingKey {
        case leagueId = "league_id"
        case name
        case season
        case seasonType = "season_type"
        case sport
        case status
        case totalRosters = "total_rosters"
        case shard
        case draftId = "draft_id"
        case previousLeagueId = "previous_league_id"
        case bracketId = "bracket_id"
        case groupId = "group_id"
        case avatar
        case settings
        case scoringSettings = "scoring_settings"
        case rosterPositions = "roster_positions"
        case metadata
    }

    // MARK: - Computed

    var displayName: String {
        guard let name, !name.isEmpty else { return "League \(leagueId)" }
        return name
    }

    var avatarURL: URL? {
        avatar.flatMap { URL(string: "https://sleepercdn.com/avatars/\($0)") }
    }

    var winnerRosterId: String? {
        metadata?["latest_league_winner_roster_id"]?.stringValue
    }

    var isDynasty: Bool {
        if let typeValue = settings?.additionalSettings?["type"]?.doubleValue, typeValue == 2 {
            return true
        }
        if metadata?["dynasty"]?.stringValue == "1" {
            return true
        }
        return false
    }

    /// Extracts division names from metadata keys like `division_1`, `division_2`, etc.
    var divisions: [Int: String] {
        guard let metadata else { return [:] }
        var result: [Int: String] = [:]
        for (key, value) in metadata {
            guard key.hasPrefix("division_"),
                  !key.hasSuffix("_avatar"),
                  let numString = key.split(separator: "_").last,
                  let num = Int(numString),
                  let name = value.stringValue else { continue }
            result[num] = name
        }
        return result
    }

    /// Extracts division avatar hashes from metadata keys like `division_1_avatar`.
    var divisionAvatars: [Int: String] {
        guard let metadata else { return [:] }
        var result: [Int: String] = [:]
        for (key, value) in metadata {
            guard key.hasPrefix("division_"),
                  key.hasSuffix("_avatar"),
                  let name = value.stringValue else { continue }
            let stripped = key.replacingOccurrences(of: "_avatar", with: "")
            if let numString = stripped.split(separator: "_").last,
               let num = Int(numString) {
                result[num] = name
            }
        }
        return result
    }
}

// MARK: - LeagueSettings

struct LeagueSettings: Codable, Sendable {
    let dailyWaivers: Int?
    let dailyWaiverHour: Int?
    let playoffRoundType: Int?
    let playoffTeams: Int?
    let playoffSeedType: Int?
    let waiverType: Int?
    let reserveSlots: Int?
    let taxiSlots: Int?
    let tradeDeadline: Int?
    let maxKeepers: Int?
    let draftRounds: Int?
    let numTeams: Int?

    /// Captures any additional settings fields not explicitly modeled.
    let additionalSettings: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case dailyWaivers = "daily_waivers"
        case dailyWaiverHour = "daily_waiver_hour"
        case playoffRoundType = "playoff_round_type"
        case playoffTeams = "playoff_teams"
        case playoffSeedType = "playoff_seed_type"
        case waiverType = "waiver_type"
        case reserveSlots = "reserve_slots"
        case taxiSlots = "taxi_slots"
        case tradeDeadline = "trade_deadline"
        case maxKeepers = "max_keepers"
        case draftRounds = "draft_rounds"
        case numTeams = "num_teams"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailyWaivers = try container.decodeIfPresent(Int.self, forKey: .dailyWaivers)
        dailyWaiverHour = try container.decodeIfPresent(Int.self, forKey: .dailyWaiverHour)
        playoffRoundType = try container.decodeIfPresent(Int.self, forKey: .playoffRoundType)
        playoffTeams = try container.decodeIfPresent(Int.self, forKey: .playoffTeams)
        playoffSeedType = try container.decodeIfPresent(Int.self, forKey: .playoffSeedType)
        waiverType = try container.decodeIfPresent(Int.self, forKey: .waiverType)
        reserveSlots = try container.decodeIfPresent(Int.self, forKey: .reserveSlots)
        taxiSlots = try container.decodeIfPresent(Int.self, forKey: .taxiSlots)
        tradeDeadline = try container.decodeIfPresent(Int.self, forKey: .tradeDeadline)
        maxKeepers = try container.decodeIfPresent(Int.self, forKey: .maxKeepers)
        draftRounds = try container.decodeIfPresent(Int.self, forKey: .draftRounds)
        numTeams = try container.decodeIfPresent(Int.self, forKey: .numTeams)

        // Decode remaining keys into additionalSettings
        let allKeysContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
        var extras: [String: AnyCodableValue] = [:]
        for key in allKeysContainer.allKeys where !knownKeys.contains(key.stringValue) {
            if let value = try? allKeysContainer.decode(AnyCodableValue.self, forKey: key) {
                extras[key.stringValue] = value
            }
        }
        additionalSettings = extras.isEmpty ? nil : extras
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(dailyWaivers, forKey: .dailyWaivers)
        try container.encodeIfPresent(dailyWaiverHour, forKey: .dailyWaiverHour)
        try container.encodeIfPresent(playoffRoundType, forKey: .playoffRoundType)
        try container.encodeIfPresent(playoffTeams, forKey: .playoffTeams)
        try container.encodeIfPresent(playoffSeedType, forKey: .playoffSeedType)
        try container.encodeIfPresent(waiverType, forKey: .waiverType)
        try container.encodeIfPresent(reserveSlots, forKey: .reserveSlots)
        try container.encodeIfPresent(taxiSlots, forKey: .taxiSlots)
        try container.encodeIfPresent(tradeDeadline, forKey: .tradeDeadline)
        try container.encodeIfPresent(maxKeepers, forKey: .maxKeepers)
        try container.encodeIfPresent(draftRounds, forKey: .draftRounds)
        try container.encodeIfPresent(numTeams, forKey: .numTeams)
        if let extras = additionalSettings {
            var allKeysContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in extras {
                try allKeysContainer.encode(value, forKey: DynamicCodingKey(stringValue: key))
            }
        }
    }
}

extension LeagueSettings.CodingKeys: CaseIterable {}

// MARK: - LeagueConfig

struct LeagueConfig: Sendable {
    let id: String
    let displayName: String
    let dynasty: Bool
    let divisions: Int
    let size: Int
    let taxi: Bool
}

// MARK: - Dynamic Coding Key

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - AnyCodableValue

/// A type-erased Codable value for handling dynamic JSON dictionaries.
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var stringValue: String? {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .bool(let b): String(b)
        case .null: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        case .string(let s): Double(s)
        default: nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): i
        case .double(let d): Int(d)
        case .string(let s): Int(s)
        default: nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }
}
