import Foundation

/// Composed at runtime from Player + roster ownership + draft metadata.
/// Not Codable -- assembled from multiple data sources.
struct TaxiSquadPlayer: Identifiable, Sendable {
    let playerId: String
    let player: Player
    let rosterId: Int
    let ownerUserId: String
    let ownerDisplayName: String
    let ownerUsername: String
    let ownerTeamName: String
    let draftRound: Int?
    let draftPickNo: Int?

    var id: String { playerId }

    var profileImageURL: URL? {
        player.profileImageURL
    }

    var thumbnailImageURL: URL? {
        player.thumbnailImageURL
    }
}
