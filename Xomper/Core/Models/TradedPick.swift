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
    /// Draft picks that changed hands in a trade. Same shape as
    /// `TradedPick` (`owner_id` = new owner, `previous_owner_id` = old).
    /// Empty/absent for waiver + free-agent moves.
    let draftPicks: [TradedPick]?
    /// FAAB transfers included in a trade (`sender`/`receiver` roster ids
    /// + `amount`). Absent for non-FAAB deals.
    let waiverBudget: [WaiverBudgetTransfer]?
    /// Per-transaction settings — carries the FAAB `waiver_bid` on a
    /// successful waiver claim.
    let settings: TransactionSettings?
    let created: Int?

    var id: String { transactionId }

    enum CodingKeys: String, CodingKey {
        case type
        case status
        case transactionId = "transaction_id"
        case rosterIds = "roster_ids"
        case adds
        case drops
        case draftPicks = "draft_picks"
        case waiverBudget = "waiver_budget"
        case settings
        case created
    }
}

/// A FAAB transfer inside a trade transaction (Sleeper `waiver_budget`).
struct WaiverBudgetTransfer: Codable, Sendable {
    let sender: Int
    let receiver: Int
    let amount: Int
}

/// Transaction-level settings. Only `waiver_bid` (the FAAB amount spent
/// on a winning waiver claim) is consumed on iOS today.
struct TransactionSettings: Codable, Sendable {
    let waiverBid: Int?
    let seq: Int?

    enum CodingKeys: String, CodingKey {
        case waiverBid = "waiver_bid"
        case seq
    }
}
