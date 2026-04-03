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
    let displayName: String?
    let role: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case sleeperUsername = "sleeper_username"
        case displayName = "display_name"
        case role
        case isActive = "is_active"
    }
}

struct SleeperUser: Codable, Identifiable, Sendable {
    let userId: String
    let username: String?
    let displayName: String?
    let avatar: String?
    let isBot: Bool?
    let isOwner: Bool?
    let metadata: [String: AnyCodableValue]?
    let settings: [String: AnyCodableValue]?

    var id: String { userId }

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
