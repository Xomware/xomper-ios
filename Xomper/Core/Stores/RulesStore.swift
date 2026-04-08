import Foundation
import Supabase

@Observable
@MainActor
final class RulesStore {

    // MARK: - State

    private(set) var proposals: [RuleProposal] = []
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var error: Error?
    private(set) var recentlyStampedIds: Set<String> = []

    var proposalFilter: ProposalFilter = .all

    var filteredProposals: [RuleProposal] {
        switch proposalFilter {
        case .all: proposals
        case .open: proposals.filter { $0.status == .open }
        case .approved: proposals.filter { $0.status == .approved }
        case .rejected: proposals.filter { $0.status == .rejected }
        }
    }

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Thresholds

    func approvalThreshold(totalRosters: Int) -> Int {
        Int(ceil(Double(totalRosters * 2) / 3.0))
    }

    func denialThreshold(totalRosters: Int) -> Int {
        totalRosters - approvalThreshold(totalRosters: totalRosters) + 1
    }

    // MARK: - Load Proposals

    func loadProposals(leagueId: String, totalRosters: Int) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let userId = try? await supabase.auth.session.user.id.uuidString

            // Fetch proposals with proposer profile
            let rows: [SupabaseProposalRow] = try await supabase
                .from("rule_proposals")
                .select("*, profiles:proposed_by ( sleeper_username, display_name, email )")
                .eq("league_id", value: leagueId)
                .order("created_at", ascending: false)
                .execute()
                .value

            guard !rows.isEmpty else {
                proposals = []
                isLoading = false
                return
            }

            let proposalIds = rows.map(\.id)

            // Fetch vote counts and user's votes in parallel
            async let yesRows = fetchVoteRows(proposalIds: proposalIds, vote: "yes")
            async let noRows = fetchVoteRows(proposalIds: proposalIds, vote: "no")
            async let myVoteRows = fetchMyVotes(proposalIds: proposalIds, userId: userId)

            let (yesCounts, noCounts, myVotes) = await (
                buildVoteCounts(try yesRows),
                buildVoteCounts(try noRows),
                buildMyVotes(try myVoteRows)
            )

            let mapped = rows.map { row in
                let proposerName = row.profiles?.displayName
                    ?? row.profiles?.sleeperUsername
                    ?? row.profiles?.email?.components(separatedBy: "@").first
                    ?? "Unknown"

                return RuleProposal(
                    id: row.id,
                    leagueId: row.leagueId,
                    proposedBy: row.proposedBy,
                    proposedByUsername: proposerName,
                    title: row.title,
                    description: row.description ?? "",
                    status: ProposalStatus(rawValue: row.status) ?? .open,
                    yesCount: yesCounts[row.id] ?? 0,
                    noCount: noCounts[row.id] ?? 0,
                    myVote: myVotes[row.id],
                    createdAt: row.createdAt
                )
            }

            // Sort: open first, then by date descending
            proposals = mapped.sorted { a, b in
                if a.status == .open && b.status != .open { return true }
                if a.status != .open && b.status == .open { return false }
                return a.createdAt > b.createdAt
            }

            // Check thresholds after loading
            await checkThresholds(totalRosters: totalRosters, leagueName: "")

        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Create Proposal

    func createProposal(
        leagueId: String,
        title: String,
        description: String,
        leagueName: String,
        proposerName: String,
        totalRosters: Int
    ) async -> Bool {
        guard let userId = try? await supabase.auth.session.user.id.uuidString else {
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await supabase
                .from("rule_proposals")
                .insert([
                    "league_id": leagueId,
                    "proposed_by": userId,
                    "title": title,
                    "description": description
                ])
                .execute()

            // Send email notification (fire-and-forget)
            Task {
                await sendProposalEmail(
                    title: title,
                    description: description,
                    proposerName: proposerName,
                    leagueName: leagueName
                )
            }

            // Reload proposals
            await loadProposals(leagueId: leagueId, totalRosters: totalRosters)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    // MARK: - Cast Vote

    func castVote(
        proposalId: String,
        vote: VoteChoice,
        leagueId: String,
        leagueName: String,
        totalRosters: Int
    ) async -> Bool {
        guard let userId = try? await supabase.auth.session.user.id.uuidString else {
            return false
        }

        do {
            try await supabase
                .from("rule_votes")
                .upsert([
                    "proposal_id": proposalId,
                    "user_id": userId,
                    "vote": vote.rawValue
                ])
                .execute()

            await loadProposals(leagueId: leagueId, totalRosters: totalRosters)
            await checkThresholds(totalRosters: totalRosters, leagueName: leagueName)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    // MARK: - Delete Proposal

    func deleteProposal(proposalId: String, leagueId: String, totalRosters: Int) async -> Bool {
        do {
            try await supabase
                .from("rule_proposals")
                .delete()
                .eq("id", value: proposalId)
                .execute()

            await loadProposals(leagueId: leagueId, totalRosters: totalRosters)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    // MARK: - Get Voter Names

    func getVoterNames(proposalId: String) async -> (approvedBy: [String], rejectedBy: [String]) {
        do {
            let rows: [SupabaseVoteWithProfileRow] = try await supabase
                .from("rule_votes")
                .select("vote, profiles:user_id ( display_name, sleeper_username, email )")
                .eq("proposal_id", value: proposalId)
                .execute()
                .value

            var approvedBy: [String] = []
            var rejectedBy: [String] = []

            for row in rows {
                let name = row.profiles?.displayName
                    ?? row.profiles?.sleeperUsername
                    ?? row.profiles?.email?.components(separatedBy: "@").first
                    ?? "Unknown"

                if row.vote == "yes" {
                    approvedBy.append(name)
                } else {
                    rejectedBy.append(name)
                }
            }

            return (approvedBy, rejectedBy)
        } catch {
            return ([], [])
        }
    }

    // MARK: - Private: Threshold Checking

    private func checkThresholds(totalRosters: Int, leagueName: String) async {
        let threshold = approvalThreshold(totalRosters: totalRosters)
        let denial = denialThreshold(totalRosters: totalRosters)

        for proposal in proposals where proposal.status == .open {
            if proposal.yesCount >= threshold {
                recentlyStampedIds.insert(proposal.id)
                let success = await updateProposalStatus(proposalId: proposal.id, status: .approved)
                if success {
                    Task {
                        await sendStatusEmail(proposal: proposal, status: .approved, leagueName: leagueName)
                    }
                }
            } else if proposal.noCount >= denial {
                recentlyStampedIds.insert(proposal.id)
                let success = await updateProposalStatus(proposalId: proposal.id, status: .rejected)
                if success {
                    Task {
                        await sendStatusEmail(proposal: proposal, status: .rejected, leagueName: leagueName)
                    }
                }
            }
        }
    }

    private func updateProposalStatus(proposalId: String, status: ProposalStatus) async -> Bool {
        do {
            try await supabase
                .from("rule_proposals")
                .update(["status": status.rawValue])
                .eq("id", value: proposalId)
                .execute()

            // Update local state
            if let index = proposals.firstIndex(where: { $0.id == proposalId }) {
                let old = proposals[index]
                proposals[index] = RuleProposal(
                    id: old.id,
                    leagueId: old.leagueId,
                    proposedBy: old.proposedBy,
                    proposedByUsername: old.proposedByUsername,
                    title: old.title,
                    description: old.description,
                    status: status,
                    yesCount: old.yesCount,
                    noCount: old.noCount,
                    myVote: old.myVote,
                    createdAt: old.createdAt
                )
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private: Supabase Queries

    private func fetchVoteRows(proposalIds: [String], vote: String) async throws -> [SupabaseVoteRow] {
        try await supabase
            .from("rule_votes")
            .select("proposal_id")
            .in("proposal_id", values: proposalIds)
            .eq("vote", value: vote)
            .execute()
            .value
    }

    private func fetchMyVotes(proposalIds: [String], userId: String?) async throws -> [SupabaseMyVoteRow] {
        guard let userId else { return [] }
        return try await supabase
            .from("rule_votes")
            .select("proposal_id, vote")
            .in("proposal_id", values: proposalIds)
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    private func buildVoteCounts(_ rows: [SupabaseVoteRow]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in rows {
            counts[row.proposalId, default: 0] += 1
        }
        return counts
    }

    private func buildMyVotes(_ rows: [SupabaseMyVoteRow]) -> [String: VoteChoice] {
        var votes: [String: VoteChoice] = [:]
        for row in rows {
            if let choice = VoteChoice(rawValue: row.vote) {
                votes[row.proposalId] = choice
            }
        }
        return votes
    }

    // MARK: - Private: Email Notifications

    private func getLeagueMembers() async -> (emails: [String], userIds: [String]) {
        do {
            let rows: [SupabaseEmailUserIdRow] = try await supabase
                .from("whitelisted_users")
                .select("email, user_id")
                .eq("is_active", value: true)
                .execute()
                .value

            let emails = rows.map(\.email).filter { !$0.isEmpty }
            let userIds = rows.compactMap(\.userId).filter { !$0.isEmpty }
            return (emails, userIds)
        } catch {
            return ([], [])
        }
    }

    private func sendProposalEmail(
        title: String,
        description: String,
        proposerName: String,
        leagueName: String
    ) async {
        let members = await getLeagueMembers()
        guard !members.emails.isEmpty else { return }

        let payload = RuleProposalEmailPayload(
            title: title,
            description: description,
            proposedByUsername: proposerName,
            leagueName: leagueName
        )

        try? await apiClient.sendRuleProposalEmail(
            proposal: payload,
            recipients: members.emails,
            userIds: members.userIds
        )
    }

    private func sendStatusEmail(
        proposal: RuleProposal,
        status: ProposalStatus,
        leagueName: String
    ) async {
        async let voterNames = getVoterNames(proposalId: proposal.id)
        async let members = getLeagueMembers()

        let (voters, leagueMembers) = await (voterNames, members)
        guard !leagueMembers.emails.isEmpty else { return }

        let payload = RuleProposalEmailPayload(
            title: proposal.title,
            description: proposal.description,
            proposedByUsername: proposal.proposedByUsername,
            leagueName: leagueName
        )

        if status == .approved {
            try? await apiClient.sendRuleAcceptedEmail(
                proposal: payload,
                approvedBy: voters.approvedBy,
                rejectedBy: voters.rejectedBy,
                recipients: leagueMembers.emails,
                userIds: leagueMembers.userIds
            )
        } else {
            try? await apiClient.sendRuleDeniedEmail(
                proposal: payload,
                approvedBy: voters.approvedBy,
                rejectedBy: voters.rejectedBy,
                recipients: leagueMembers.emails,
                userIds: leagueMembers.userIds
            )
        }
    }

    // MARK: - Reset

    func reset() {
        proposals = []
        isLoading = false
        isSubmitting = false
        error = nil
        recentlyStampedIds = []
        proposalFilter = .all
    }
}

// MARK: - Proposal Filter

enum ProposalFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case approved = "Approved"
    case rejected = "Denied"

    var id: String { rawValue }
}

// MARK: - Supabase Row Types

private struct SupabaseProposalRow: Decodable, Sendable {
    let id: String
    let leagueId: String
    let proposedBy: String
    let title: String
    let description: String?
    let status: String
    let createdAt: String
    let profiles: SupabaseProfileJoin?

    enum CodingKeys: String, CodingKey {
        case id
        case leagueId = "league_id"
        case proposedBy = "proposed_by"
        case title
        case description
        case status
        case createdAt = "created_at"
        case profiles
    }
}

private struct SupabaseProfileJoin: Decodable, Sendable {
    let sleeperUsername: String?
    let displayName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case sleeperUsername = "sleeper_username"
        case displayName = "display_name"
        case email
    }
}

private struct SupabaseVoteRow: Decodable, Sendable {
    let proposalId: String

    enum CodingKeys: String, CodingKey {
        case proposalId = "proposal_id"
    }
}

private struct SupabaseMyVoteRow: Decodable, Sendable {
    let proposalId: String
    let vote: String

    enum CodingKeys: String, CodingKey {
        case proposalId = "proposal_id"
        case vote
    }
}

private struct SupabaseVoteWithProfileRow: Decodable, Sendable {
    let vote: String
    let profiles: SupabaseProfileJoin?
}

private struct SupabaseEmailUserIdRow: Decodable, Sendable {
    let email: String
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case email
        case userId = "user_id"
    }
}
