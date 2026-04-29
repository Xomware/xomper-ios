import Foundation

struct XomperProfile: Codable, Sendable {
    let id: String
    let email: String?
    let sleeperUserId: String?
    let sleeperUsername: String?
    let sleeperAvatar: String?
    let displayName: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case sleeperUserId = "sleeper_user_id"
        case sleeperUsername = "sleeper_username"
        case sleeperAvatar = "sleeper_avatar"
        case displayName = "display_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct WhitelistedUser: Codable, Sendable {
    let id: String
    let email: String
    let sleeperUsername: String?
    let sleeperUserId: String?
    let displayName: String?
    let role: String?
    let isActive: Bool
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case sleeperUsername = "sleeper_username"
        case sleeperUserId = "sleeper_user_id"
        case displayName = "display_name"
        case role
        case isActive = "is_active"
        case isAdmin = "is_admin"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        sleeperUsername = try c.decodeIfPresent(String.self, forKey: .sleeperUsername)
        sleeperUserId = try c.decodeIfPresent(String.self, forKey: .sleeperUserId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        isActive = (try? c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? false
        isAdmin = (try? c.decodeIfPresent(Bool.self, forKey: .isAdmin)) ?? false
    }
}

struct SleeperUser: Codable, Identifiable, Sendable {
    let userId: String?
    let username: String?
    let displayName: String?
    let avatar: String?
    let isBot: Bool?
    let isOwner: Bool?
    let metadata: [String: AnyCodableValue]?
    let settings: [String: AnyCodableValue]?

    var id: String { userId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatar
        case isBot = "is_bot"
        case isOwner = "is_owner"
        case metadata
        case settings
    }

    // MARK: - Computed

    var resolvedDisplayName: String {
        displayName ?? username ?? "Unknown"
    }

    var avatarURL: URL? {
        avatar.flatMap { URL(string: "https://sleepercdn.com/avatars/\($0)") }
    }

    var teamName: String? {
        metadata?["team_name"]?.stringValue
    }
}
