import Foundation

struct TradedPick: Codable, Identifiable, Sendable {
    let season: String
    let round: Int
    let rosterId: Int
    let previousOwnerId: Int
    let ownerId: Int

    var id: String { "\(season)-\(round)-\(rosterId)-\(ownerId)" }

    enum CodingKeys: String, CodingKey {
        case season
        case round
        case rosterId = "roster_id"
        case previousOwnerId = "previous_owner_id"
        case ownerId = "owner_id"
    }
}

// MARK: - Transaction

struct Transaction: Codable, Identifiable, Sendable {
    let type: String?
    let status: String?
    let transactionId: String
    let rosterIds: [Int]?
    let adds: [String: Int]?
    let drops: [String: Int]?
    let created: Int?

    var id: String { transactionId }

    enum CodingKeys: String, CodingKey {
        case type
        case status
        case transactionId = "transaction_id"
        case rosterIds = "roster_ids"
        case adds
        case drops
        case created
    }
}
