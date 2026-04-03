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
    let depthChartPosition: Int?
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
