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

/// Mirrors a row in the Supabase `whitelisted_users` table. Used in
/// two places:
/// 1. `AuthStore.whitelistedUser` — the current signed-in user's row.
/// 2. F4 Admin Tables surface — `AdminTablesStore.users` lists every
///    row for the Users editor.
///
/// `id` is the Supabase row UUID. `sleeperUserId` is the Sleeper
/// identity (optional in the wire shape since the row can exist
/// before the user finishes the OAuth handshake) and is the key
/// the F4 admin endpoints accept.
///
/// Memberwise + decode init are both defined so the F4 store can
/// build the model in-memory after a successful update without
/// re-fetching from Supabase.
struct WhitelistedUser: Codable, Sendable, Identifiable, Hashable {
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

    /// Memberwise init for tests / previews and for in-place
    /// mutation by `AdminTablesStore.updateUser`.
    init(
        id: String,
        email: String,
        sleeperUsername: String? = nil,
        sleeperUserId: String? = nil,
        displayName: String? = nil,
        role: String? = nil,
        isActive: Bool,
        isAdmin: Bool
    ) {
        self.id = id
        self.email = email
        self.sleeperUsername = sleeperUsername
        self.sleeperUserId = sleeperUserId
        self.displayName = displayName
        self.role = role
        self.isActive = isActive
        self.isAdmin = isAdmin
    }

    /// Stable identity key for F4 admin update calls. Backend keys
    /// on `sleeper_user_id` when present, falling back to the row
    /// UUID — same fallback iOS uses for `Identifiable.id` here.
    var updateKey: String {
        sleeperUserId ?? id
    }

    /// Resolved name for list rendering — display name preferred,
    /// then sleeper username, then a placeholder.
    var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let sleeperUsername, !sleeperUsername.isEmpty { return sleeperUsername }
        return "(unnamed)"
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
