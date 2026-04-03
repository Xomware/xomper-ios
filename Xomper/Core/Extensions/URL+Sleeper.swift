import Foundation

extension URL {
    /// Sleeper CDN avatar URL for a given avatar ID.
    static func sleeperAvatar(for avatarId: String?) -> URL? {
        guard let avatarId, !avatarId.isEmpty else { return nil }
        return URL(string: "https://sleepercdn.com/avatars/thumbs/\(avatarId)")
    }

    /// Sleeper CDN player headshot URL for a given player ID.
    static func sleeperPlayerImage(for playerId: String) -> URL? {
        URL(string: "https://sleepercdn.com/content/nfl/players/thumb/\(playerId).jpg")
    }
}
