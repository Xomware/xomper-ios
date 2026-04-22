import Foundation
@preconcurrency import Supabase

// MARK: - Supabase Response Types

private struct StealRequestRow: Decodable, Sendable {
    let playerID: String

    enum CodingKeys: String, CodingKey {
        case playerID = "player_id"
    }
}

private struct OwnerEmailRow: Decodable, Sendable {
    let email: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName = "display_name"
    }
}

private struct MemberEmailRow: Decodable, Sendable {
    let email: String
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case email
        case userId = "user_id"
    }
}

// MARK: - TaxiSquadStore

@Observable
@MainActor
final class TaxiSquadStore {

    // MARK: - State

    private(set) var players: [TaxiSquadPlayer] = []
    private(set) var stolenPlayerIds: Set<String> = []
    private(set) var isLoading = false
    private(set) var isSubmittingSteal = false
    private(set) var error: Error?
    private(set) var stealError: Error?

    // MARK: - Dependencies

    private let apiClient: SleeperAPIClientProtocol
    private let xomperAPIClient: XomperAPIClientProtocol

    init(
        apiClient: SleeperAPIClientProtocol = SleeperAPIClient(),
        xomperAPIClient: XomperAPIClientProtocol = XomperAPIClient()
    ) {
        self.apiClient = apiClient
        self.xomperAPIClient = xomperAPIClient
    }

    // MARK: - Load Taxi Squad Players

    /// Iterates all rosters' taxi arrays, resolves player data + draft pick metadata,
    /// and builds the full TaxiSquadPlayer array.
    func loadTaxiSquadPlayers(
        rosters: [Roster],
        users: [SleeperUser],
        playerStore: PlayerStore,
        leagueId: String
    ) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            // Fetch all drafts and their picks for the league
            let drafts = try await apiClient.fetchDrafts(leagueId)
            let allPicks = try await fetchAllDraftPicks(drafts: drafts)

            var taxiPlayers: [TaxiSquadPlayer] = []

            for roster in rosters {
                guard let taxiIds = roster.taxi, !taxiIds.isEmpty else { continue }

                let ownerUser = users.first { $0.userId == roster.ownerId }

                for playerId in taxiIds {
                    guard let player = playerStore.player(for: playerId) else { continue }

                    let draftPick = allPicks.first { $0.playerId == playerId }

                    let taxiPlayer = TaxiSquadPlayer(
                        playerId: playerId,
                        player: player,
                        rosterId: roster.rosterId,
                        ownerUserId: ownerUser?.userId ?? "",
                        ownerDisplayName: ownerUser?.resolvedDisplayName ?? "",
                        ownerUsername: ownerUser?.username ?? "",
                        ownerTeamName: ownerUser?.teamName ?? "",
                        draftRound: draftPick?.round,
                        draftPickNo: draftPick?.draftSlot
                    )

                    taxiPlayers.append(taxiPlayer)
                }
            }

            // Sort by position priority then name
            let positionOrder = ["QB", "RB", "WR", "TE", "K", "DEF"]
            taxiPlayers.sort { a, b in
                let aIdx = positionOrder.firstIndex(of: a.player.displayPosition) ?? 99
                let bIdx = positionOrder.firstIndex(of: b.player.displayPosition) ?? 99
                if aIdx != bIdx { return aIdx < bIdx }
                return a.player.fullDisplayName < b.player.fullDisplayName
            }

            players = taxiPlayers
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Steal Requests

    /// Fetches existing steal request player IDs for this league from Supabase.
    func loadStealRequests(leagueId: String) async {
        do {
            let rows: [StealRequestRow] = try await supabase
                .from("taxi_steal_requests")
                .select("player_id")
                .eq("league_id", value: leagueId)
                .execute()
                .value

            stolenPlayerIds = Set(rows.map(\.playerID))
        } catch {
            // Non-fatal -- just means we can't show existing steals
            stolenPlayerIds = []
        }
    }

    /// Submits a steal request: inserts into Supabase and sends email notification.
    func submitStealRequest(
        player: TaxiSquadPlayer,
        stealerName: String,
        leagueId: String,
        leagueName: String
    ) async -> Bool {
        guard !isSubmittingSteal else { return false }

        guard let userId = try? await supabase.auth.session.user.id.uuidString else {
            stealError = TaxiSquadError.notAuthenticated
            return false
        }

        isSubmittingSteal = true
        stealError = nil

        do {
            // 1. Insert steal request into Supabase
            try await supabase
                .from("taxi_steal_requests")
                .insert([
                    "league_id": leagueId,
                    "player_id": player.playerId,
                    "requested_by": userId,
                    "requested_by_name": stealerName
                ])
                .execute()

            // 2. Fetch owner email and all league members in parallel
            async let ownerInfoTask = fetchOwnerEmail(sleeperUsername: player.ownerUsername)
            async let membersTask = fetchLeagueMembers()

            let ownerInfo = await ownerInfoTask
            let members = await membersTask

            // 3. Send email notification (fire and forget, don't block on failure)
            let team = player.player.displayTeam
            let pickCost = Self.stealPickText(for: player.draftRound)

            let stealerPayload = TaxiStealerPayload(displayName: stealerName)
            let playerPayload = TaxiPlayerPayload(
                firstName: player.player.firstName ?? "",
                lastName: player.player.lastName ?? "",
                position: player.player.displayPosition,
                team: team,
                playerImageUrl: player.thumbnailImageURL?.absoluteString ?? "",
                teamLogoUrl: player.player.teamLogoURL?.absoluteString ?? "",
                pickCost: pickCost
            )
            let ownerPayload = TaxiOwnerPayload(
                displayName: ownerInfo?.displayName ?? player.ownerDisplayName,
                email: ownerInfo?.email ?? ""
            )

            try? await xomperAPIClient.sendTaxiStealEmail(
                stealer: stealerPayload,
                player: playerPayload,
                owner: ownerPayload,
                recipients: members.emails,
                userIds: members.userIds,
                leagueName: leagueName
            )

            // 4. Update local state
            stolenPlayerIds.insert(player.playerId)
            isSubmittingSteal = false
            return true
        } catch {
            stealError = error
            isSubmittingSteal = false
            return false
        }
    }

    // MARK: - Pick Cost Calculation

    /// Returns the pick round text for a steal. Steal costs one round higher than drafted.
    /// Undrafted or round 1 players cost a 5th round pick.
    static func stealPickText(for draftRound: Int?) -> String {
        guard let draftRound, draftRound > 0 else {
            return "5th Round"
        }

        let stealRound = draftRound - 1
        if stealRound <= 0 {
            return "5th Round"
        }

        return "\(ordinal(stealRound)) Round"
    }

    // MARK: - Reset

    func reset() {
        players = []
        stolenPlayerIds = []
        error = nil
        stealError = nil
    }

    // MARK: - Private Helpers

    /// Fetches all draft picks across all drafts concurrently.
    private func fetchAllDraftPicks(drafts: [Draft]) async throws -> [DraftPick] {
        try await withThrowingTaskGroup(of: [DraftPick].self) { group in
            for draft in drafts {
                group.addTask { [apiClient] in
                    do {
                        return try await apiClient.fetchDraftPicks(draft.draftId)
                    } catch {
                        return []
                    }
                }
            }

            var allPicks: [DraftPick] = []
            for try await picks in group {
                allPicks.append(contentsOf: picks)
            }
            return allPicks
        }
    }

    /// Looks up owner email and display name from whitelisted_users by Sleeper username.
    private func fetchOwnerEmail(sleeperUsername: String?) async -> OwnerEmailRow? {
        guard let username = sleeperUsername, !username.isEmpty else { return nil }

        do {
            let row: OwnerEmailRow = try await supabase
                .from("whitelisted_users")
                .select("email, display_name")
                .eq("sleeper_username", value: username)
                .eq("is_active", value: true)
                .limit(1)
                .single()
                .execute()
                .value
            return row
        } catch {
            return nil
        }
    }

    /// Fetches all active league member emails and user IDs from whitelisted_users.
    private func fetchLeagueMembers() async -> (emails: [String], userIds: [String]) {
        do {
            let rows: [MemberEmailRow] = try await supabase
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

    /// Returns the ordinal suffix for a number (1st, 2nd, 3rd, etc.).
    private static func ordinal(_ n: Int) -> String {
        let suffixes = ["th", "st", "nd", "rd"]
        let remainder = n % 100
        let suffix = suffixes[(remainder - 20) % 10 >= 0 ? (remainder - 20) % 10 : remainder] ?? suffixes[0]
        let safeSuffix: String
        if (11...13).contains(remainder) {
            safeSuffix = "th"
        } else {
            switch remainder % 10 {
            case 1: safeSuffix = "st"
            case 2: safeSuffix = "nd"
            case 3: safeSuffix = "rd"
            default: safeSuffix = "th"
            }
        }
        return "\(n)\(safeSuffix)"
    }
}

// MARK: - Errors

enum TaxiSquadError: Error, LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "You must be signed in to submit a steal request."
        }
    }
}
