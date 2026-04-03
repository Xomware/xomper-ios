import Foundation

struct RuleProposal: Codable, Identifiable, Sendable {
    let id: String
    let leagueId: String
    let proposedBy: String
    let proposedByUsername: String
    let title: String
    let description: String
    let status: ProposalStatus
    let yesCount: Int
    let noCount: Int
    let myVote: VoteChoice?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case leagueId = "league_id"
        case proposedBy = "proposed_by"
        case proposedByUsername = "proposed_by_username"
        case title
        case description
        case status
        case yesCount = "yes_count"
        case noCount = "no_count"
        case myVote = "my_vote"
        case createdAt = "created_at"
    }

    var totalVotes: Int {
        yesCount + noCount
    }
}

// MARK: - ProposalStatus

enum ProposalStatus: String, Codable, Sendable, CaseIterable {
    case open
    case approved
    case rejected
    case closed
}

// MARK: - VoteChoice

enum VoteChoice: String, Codable, Sendable {
    case yes
    case no
}

// MARK: - RuleVote

struct RuleVote: Codable, Sendable {
    let proposalId: String
    let userId: String
    let vote: VoteChoice

    enum CodingKeys: String, CodingKey {
        case proposalId = "proposal_id"
        case userId = "user_id"
        case vote
    }
}
