import Foundation

struct Player: Codable, Identifiable, Sendable {
    let playerId: String
    let firstName: String?
    let lastName: String?
    let fullName: String?
    let position: String?
    let team: String?
    let age: Int?
    let college: String?
    let yearsExp: Int?
    let status: String?
    let injuryStatus: String?
    let number: Int?
    let height: String?
    let weight: String?
    let sport: String?
    let active: Bool?
    let fantasyPositions: [String]?
    let searchFullName: String?
    let searchFirstName: String?
    let searchLastName: String?
    /// Sleeper returns this as a slot label string ("QB1", "RCB", "OL"…),
    /// NOT a numeric position. iOS prior to this fix declared it `Int?`,
    /// which made the strict JSONDecoder throw on every player with a
    /// non-null value — and since `[String: Player]` decodes
    /// transactionally, the whole 11k-player load failed silently. That
    /// is the entire reason "no players are loading" was happening in
    /// production while web (TypeScript types are erased at runtime)
    /// shrugged it off.
    let depthChartPosition: String?
    let depthChartOrder: Int?
    let searchRank: Int?

    var id: String { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case fullName = "full_name"
        case position
        case team
        case age
        case college
        case yearsExp = "years_exp"
        case status
        case injuryStatus = "injury_status"
        case number
        case height
        case weight
        case sport
        case active
        case fantasyPositions = "fantasy_positions"
        case searchFullName = "search_full_name"
        case searchFirstName = "search_first_name"
        case searchLastName = "search_last_name"
        case depthChartPosition = "depth_chart_position"
        case depthChartOrder = "depth_chart_order"
        case searchRank = "search_rank"
    }

    /// Lenient decoder: every optional field uses `try?` so a single
    /// type mismatch in Sleeper's response (e.g., a future field that
    /// drifts from int → string) degrades the affected field to `nil`
    /// instead of taking down the entire `[String: Player]` decode.
    /// `playerId` is the only required field and is the dictionary key
    /// in the parent decode anyway.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.playerId = try c.decode(String.self, forKey: .playerId)
        self.firstName = try? c.decodeIfPresent(String.self, forKey: .firstName)
        self.lastName = try? c.decodeIfPresent(String.self, forKey: .lastName)
        self.fullName = try? c.decodeIfPresent(String.self, forKey: .fullName)
        self.position = try? c.decodeIfPresent(String.self, forKey: .position)
        self.team = try? c.decodeIfPresent(String.self, forKey: .team)
        self.age = try? c.decodeIfPresent(Int.self, forKey: .age)
        self.college = try? c.decodeIfPresent(String.self, forKey: .college)
        self.yearsExp = try? c.decodeIfPresent(Int.self, forKey: .yearsExp)
        self.status = try? c.decodeIfPresent(String.self, forKey: .status)
        self.injuryStatus = try? c.decodeIfPresent(String.self, forKey: .injuryStatus)
        self.number = try? c.decodeIfPresent(Int.self, forKey: .number)
        self.height = try? c.decodeIfPresent(String.self, forKey: .height)
        self.weight = try? c.decodeIfPresent(String.self, forKey: .weight)
        self.sport = try? c.decodeIfPresent(String.self, forKey: .sport)
        self.active = try? c.decodeIfPresent(Bool.self, forKey: .active)
        self.fantasyPositions = try? c.decodeIfPresent([String].self, forKey: .fantasyPositions)
        self.searchFullName = try? c.decodeIfPresent(String.self, forKey: .searchFullName)
        self.searchFirstName = try? c.decodeIfPresent(String.self, forKey: .searchFirstName)
        self.searchLastName = try? c.decodeIfPresent(String.self, forKey: .searchLastName)
        self.depthChartPosition = try? c.decodeIfPresent(String.self, forKey: .depthChartPosition)
        self.depthChartOrder = try? c.decodeIfPresent(Int.self, forKey: .depthChartOrder)
        self.searchRank = try? c.decodeIfPresent(Int.self, forKey: .searchRank)
    }

    /// Memberwise initializer preserved for in-app construction
    /// (preview fixtures, search results, taxi-squad players).
    init(
        playerId: String,
        firstName: String? = nil,
        lastName: String? = nil,
        fullName: String? = nil,
        position: String? = nil,
        team: String? = nil,
        age: Int? = nil,
        college: String? = nil,
        yearsExp: Int? = nil,
        status: String? = nil,
        injuryStatus: String? = nil,
        number: Int? = nil,
        height: String? = nil,
        weight: String? = nil,
        sport: String? = nil,
        active: Bool? = nil,
        fantasyPositions: [String]? = nil,
        searchFullName: String? = nil,
        searchFirstName: String? = nil,
        searchLastName: String? = nil,
        depthChartPosition: String? = nil,
        depthChartOrder: Int? = nil,
        searchRank: Int? = nil
    ) {
        self.playerId = playerId
        self.firstName = firstName
        self.lastName = lastName
        self.fullName = fullName
        self.position = position
        self.team = team
        self.age = age
        self.college = college
        self.yearsExp = yearsExp
        self.status = status
        self.injuryStatus = injuryStatus
        self.number = number
        self.height = height
        self.weight = weight
        self.sport = sport
        self.active = active
        self.fantasyPositions = fantasyPositions
        self.searchFullName = searchFullName
        self.searchFirstName = searchFirstName
        self.searchLastName = searchLastName
        self.depthChartPosition = depthChartPosition
        self.depthChartOrder = depthChartOrder
        self.searchRank = searchRank
    }

    // MARK: - Computed

    var fullDisplayName: String {
        if let fullName, !fullName.isEmpty {
            return fullName
        }
        let first = firstName ?? ""
        let last = lastName ?? ""
        let combined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? "Unknown" : combined
    }

    var displayPosition: String {
        position ?? fantasyPositions?.first ?? "N/A"
    }

    var displayTeam: String {
        team ?? "FA"
    }

    var isInjured: Bool {
        injuryStatus != nil
    }

    var profileImageURL: URL? {
        URL(string: "https://sleepercdn.com/content/nfl/players/\(playerId).jpg")
    }

    var thumbnailImageURL: URL? {
        URL(string: "https://sleepercdn.com/content/nfl/players/thumb/\(playerId).jpg")
    }

    var teamLogoURL: URL? {
        guard let team, !team.isEmpty else { return nil }
        return URL(string: "https://sleepercdn.com/images/team_logos/nfl/\(team.lowercased()).png")
    }
}
