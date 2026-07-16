import Foundation

/// Fetches league transactions across the season and turns them into a
/// graded, filterable News feed. Reads dynasty values from the shared
/// `PlayerValuesStore` (draft picks valued at the Mid tier per #145) and
/// player names from `PlayerStore`.
///
/// No backend round-trip — Sleeper's per-week transactions endpoint is
/// hit directly (there's no "all transactions" call), then each move is
/// enriched with a deterministic local write-up + trade grade. Email
/// delivery of this content is a backend follow-up, out of scope here.
@Observable
@MainActor
final class NewsStore {

    // MARK: - State

    private(set) var items: [NewsItem] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var lastLoadedLeagueId: String?
    private(set) var lastLoadedAt: Date?

    /// rosterId → team name for every team that appears in the feed.
    /// Drives the team filter chips.
    private(set) var teamNames: [Int: String] = [:]

    // MARK: - Filters

    var typeFilter: NewsType?
    var teamFilter: Int?
    var dateFilter: NewsDateWindow = .all

    // MARK: - Dependencies

    private let apiClient: SleeperAPIClientProtocol

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
    }

    /// Weeks scanned. A full NFL season is 18 weeks; scanning the whole
    /// range captures in-season moves plus offseason dynasty trades,
    /// which Sleeper logs under the current league's early weeks.
    private let weekRange = 1...18

    // MARK: - Derived

    var hasItems: Bool { !items.isEmpty }

    /// Items after the active type/team/date filters, newest first.
    var filteredItems: [NewsItem] {
        items.filter { item in
            (typeFilter == nil || item.type == typeFilter)
                && (teamFilter == nil || item.involves(rosterId: teamFilter!))
                && dateFilter.contains(item.createdAt)
        }
    }

    /// Teams that appear in the feed, sorted by name — for the team chips.
    var availableTeams: [(rosterId: Int, name: String)] {
        teamNames
            .map { (rosterId: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var activeFilterCount: Int {
        [typeFilter != nil, teamFilter != nil, dateFilter != .all].filter { $0 }.count
    }

    func clearFilters() {
        typeFilter = nil
        teamFilter = nil
        dateFilter = .all
    }

    /// Look up a news item by its transaction id.
    func item(for transactionId: String) -> NewsItem? {
        items.first { $0.id == transactionId }
    }

    // MARK: - Load

    /// Fetch + build the feed. Skips the network when the same league was
    /// loaded within the last 10 minutes and already has items, unless
    /// `forceRefresh` is set (pull-to-refresh).
    ///
    /// - Parameter draftHistory: Historical draft picks used to resolve
    ///   who a traded pick eventually became (e.g. "2024 1st → Caleb Williams").
    ///   Pass an empty array to skip resolution.
    func load(
        leagueId: String,
        rosters: [Roster],
        users: [SleeperUser],
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore,
        draftHistory: [DraftHistoryRecord] = [],
        forceRefresh: Bool = false
    ) async {
        guard !isLoading else { return }
        guard !leagueId.isEmpty else { return }

        if !forceRefresh,
           leagueId == lastLoadedLeagueId,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < 10 * 60,
           !items.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }
        error = nil

        // Drafts carry `slot_to_roster_id` — the authoritative slot↔roster
        // mapping used to resolve traded picks to their real slot.
        let drafts = (try? await apiClient.fetchDrafts(leagueId)) ?? []
        let slotByRosterIdBySeason = Self.buildSlotByRosterIdBySeason(
            leagues: [drafts],
            draftHistory: draftHistory
        )

        // Fetch every week concurrently; tolerate per-week failures so a
        // single bad week doesn't blank the feed. Weeks with no moves
        // return an empty array, not an error.
        var collected: [(week: Int, txn: Transaction)] = []
        await withTaskGroup(of: (Int, [Transaction]).self) { group in
            for week in weekRange {
                group.addTask { [apiClient] in
                    let txns = (try? await apiClient.fetchTransactions(leagueId, week: week)) ?? []
                    return (week, txns)
                }
            }
            for await (week, txns) in group {
                for txn in txns { collected.append((week, txn)) }
            }
        }

        var built: [NewsItem] = []
        var seen = Set<String>()
        for entry in collected {
            guard !seen.contains(entry.txn.transactionId) else { continue }
            if let item = NewsBuilder.build(
                transaction: entry.txn,
                week: entry.week,
                rosters: rosters,
                users: users,
                playerStore: playerStore,
                valuesStore: valuesStore,
                draftHistory: draftHistory,
                slotByRosterIdBySeason: slotByRosterIdBySeason
            ) {
                built.append(item)
                seen.insert(entry.txn.transactionId)
            }
        }

        built.sort { $0.createdAt > $1.createdAt }

        var names: [Int: String] = [:]
        for item in built {
            for side in item.sides {
                names[side.rosterId] = side.teamName
            }
        }

        items = built
        teamNames = names
        lastLoadedLeagueId = leagueId
        lastLoadedAt = Date()
    }

    /// Load transactions from ALL leagues in a chain (multiple seasons of
    /// the same dynasty). This enables showing historical trades from
    /// previous seasons, not just the current one.
    ///
    /// Each league in the chain gets its own roster/user context since
    /// team names and roster IDs can change between seasons.
    func loadFromChain(
        chain: [League],
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore,
        draftHistory: [DraftHistoryRecord] = [],
        forceRefresh: Bool = false
    ) async {
        guard !isLoading else { return }
        guard let firstLeague = chain.first else { return }

        let chainKey = chain.map(\.leagueId).joined(separator: "-")
        if !forceRefresh,
           chainKey == lastLoadedLeagueId,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < 10 * 60,
           !items.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }
        error = nil

        // Intermediate type to hold fetched data before building NewsItems.
        struct LeagueData: Sendable {
            let rosters: [Roster]
            let users: [SleeperUser]
            let drafts: [Draft]
            let transactions: [(week: Int, txn: Transaction)]
        }

        // Fetch transactions from each league in the chain concurrently.
        // Each league needs its own rosters/users context.
        var allLeagueData: [LeagueData] = []
        await withTaskGroup(of: LeagueData?.self) { group in
            for league in chain {
                group.addTask { [apiClient] in
                    // Fetch rosters and users for this league
                    let rosters = (try? await apiClient.fetchLeagueRosters(league.leagueId)) ?? []
                    let users = (try? await apiClient.fetchLeagueUsers(league.leagueId)) ?? []
                    // Drafts carry `slot_to_roster_id` — the authoritative
                    // slot↔roster mapping used to resolve traded picks.
                    let drafts = (try? await apiClient.fetchDrafts(league.leagueId)) ?? []

                    // Fetch all weeks of transactions for this league
                    var collected: [(week: Int, txn: Transaction)] = []
                    await withTaskGroup(of: (Int, [Transaction]).self) { weekGroup in
                        for week in 1...18 {
                            weekGroup.addTask {
                                let txns = (try? await apiClient.fetchTransactions(league.leagueId, week: week)) ?? []
                                return (week, txns)
                            }
                        }
                        for await (week, txns) in weekGroup {
                            for txn in txns { collected.append((week, txn)) }
                        }
                    }

                    return LeagueData(rosters: rosters, users: users, drafts: drafts, transactions: collected)
                }
            }

            for await leagueData in group {
                if let data = leagueData {
                    allLeagueData.append(data)
                }
            }
        }

        // Build the authoritative season → (roster → slot) mapping from
        // every draft's `slot_to_roster_id`. Roster IDs are stable across
        // a dynasty chain but the slot order changes each season (draft
        // lottery), so the map MUST be keyed by season — a global merge
        // would collide (roster 11 = slot 9 one year, slot 3 the next).
        let slotByRosterIdBySeason = Self.buildSlotByRosterIdBySeason(
            leagues: allLeagueData.map { ($0.drafts) },
            draftHistory: draftHistory
        )

        // Build NewsItems on the main actor (where NewsBuilder.build lives).
        var allBuilt: [NewsItem] = []
        var seen = Set<String>()
        var allTeamNames: [Int: String] = [:]

        for leagueData in allLeagueData {
            for entry in leagueData.transactions {
                guard !seen.contains(entry.txn.transactionId) else { continue }
                if let item = NewsBuilder.build(
                    transaction: entry.txn,
                    week: entry.week,
                    rosters: leagueData.rosters,
                    users: leagueData.users,
                    playerStore: playerStore,
                    valuesStore: valuesStore,
                    draftHistory: draftHistory,
                    slotByRosterIdBySeason: slotByRosterIdBySeason
                ) {
                    allBuilt.append(item)
                    seen.insert(entry.txn.transactionId)
                    for side in item.sides {
                        allTeamNames[side.rosterId] = side.teamName
                    }
                }
            }
        }

        allBuilt.sort { $0.createdAt > $1.createdAt }

        items = allBuilt
        teamNames = allTeamNames
        lastLoadedLeagueId = chainKey
        lastLoadedAt = Date()
    }

    /// Builds `season → (rosterId → draftSlot)` from each league's drafts.
    ///
    /// The authoritative source is `Draft.slot_to_roster_id` (slot → roster),
    /// inverted here to roster → slot. `TradedPick.rosterId` is the ORIGINAL
    /// slot owner, so this is exactly what turns a traded pick into its
    /// physical slot (and thus its "2.09" label + exact value).
    ///
    /// For any season where no draft has an assigned order yet (future
    /// picks), we fall back to the round-1 draft-history heuristic — imperfect
    /// when round-1 picks were themselves traded, but the best available
    /// signal before the draft order exists.
    static func buildSlotByRosterIdBySeason(
        leagues: [[Draft]],
        draftHistory: [DraftHistoryRecord]
    ) -> [String: [Int: Int]] {
        var bySeason: [String: [Int: Int]] = [:]

        for drafts in leagues {
            for draft in drafts {
                let inverted = draft.slotByRosterId
                guard !inverted.isEmpty else { continue }
                // A season has one draft; if somehow multiple, merge.
                bySeason[draft.season, default: [:]].merge(inverted) { _, new in new }
            }
        }

        // Fallback only for seasons with no authoritative map.
        let authoritative = Set(bySeason.keys)
        for record in draftHistory where record.round == 1 {
            guard !authoritative.contains(record.season) else { continue }
            bySeason[record.season, default: [:]][record.pickedByRosterId] = record.draftSlot
        }

        return bySeason
    }

    func reset() {
        items = []
        teamNames = [:]
        error = nil
        lastLoadedLeagueId = nil
        lastLoadedAt = nil
        clearFilters()
    }
}

// MARK: - NewsDateWindow

/// Recency filter for the news feed.
enum NewsDateWindow: String, CaseIterable, Identifiable, Sendable, Hashable {
    case all
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:    "All"
        case .week:   "Past Week"
        case .month:  "Past Month"
        }
    }

    func contains(_ date: Date) -> Bool {
        switch self {
        case .all:
            return true
        case .week:
            return date >= Date().addingTimeInterval(-7 * 24 * 60 * 60)
        case .month:
            return date >= Date().addingTimeInterval(-30 * 24 * 60 * 60)
        }
    }
}

// MARK: - NewsBuilder

/// Turns a raw Sleeper `Transaction` into a graded `NewsItem` with a
/// deterministic, LLM-free write-up. `@MainActor` because it reads the
/// player + value stores.
@MainActor
enum NewsBuilder {

    static func build(
        transaction t: Transaction,
        week: Int,
        rosters: [Roster],
        users: [SleeperUser],
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore,
        draftHistory: [DraftHistoryRecord] = [],
        slotByRosterIdBySeason: [String: [Int: Int]] = [:]
    ) -> NewsItem? {
        // Only surface completed, recognized moves.
        guard t.status == nil || t.status == "complete" else { return nil }
        guard let type = NewsType(sleeperType: t.type) else { return nil }

        let rosterIds = t.rosterIds ?? []
        guard !rosterIds.isEmpty else { return nil }

        let createdAt = Date(timeIntervalSince1970: Double(t.created ?? 0) / 1000.0)

        let sides: [NewsSide] = rosterIds.map { rid in
            let acquired = playerAssets(from: t.adds, roster: rid, playerStore: playerStore, valuesStore: valuesStore)
                + pickAssets(from: t.draftPicks, roster: rid, acquired: true, valuesStore: valuesStore, draftHistory: draftHistory, slotByRosterIdBySeason: slotByRosterIdBySeason)
            let relinquished = playerAssets(from: t.drops, roster: rid, playerStore: playerStore, valuesStore: valuesStore)
                + pickAssets(from: t.draftPicks, roster: rid, acquired: false, valuesStore: valuesStore, draftHistory: draftHistory, slotByRosterIdBySeason: slotByRosterIdBySeason)
            return NewsSide(
                rosterId: rid,
                teamName: teamName(rid, rosters: rosters, users: users),
                acquired: acquired,
                relinquished: relinquished,
                faab: faab(for: rid, transaction: t, type: type)
            )
        }

        // Drop no-op moves (nothing actually changed hands).
        guard sides.contains(where: { !$0.acquired.isEmpty || !$0.relinquished.isEmpty }) else {
            return nil
        }

        let grade: TradeGrade? = {
            guard type == .trade, sides.count == 2 else { return nil }
            return TradeGrade.grade(
                sideA: (sides[0].rosterId, sides[0].acquiredValue),
                sideB: (sides[1].rosterId, sides[1].acquiredValue)
            )
        }()

        return NewsItem(
            id: t.transactionId,
            type: type,
            week: week,
            createdAt: createdAt,
            rosterIds: rosterIds,
            sides: sides,
            grade: grade,
            headline: headline(type: type, sides: sides),
            summary: summary(type: type, sides: sides, grade: grade)
        )
    }

    // MARK: Asset building

    private static func playerAssets(
        from map: [String: Int]?,
        roster rid: Int,
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore
    ) -> [NewsAsset] {
        guard let map else { return [] }
        return map.compactMap { pid, owner -> NewsAsset? in
            guard owner == rid else { return nil }
            let player = playerStore.player(for: pid)
            let pos = player?.displayPosition ?? valuesStore.position(for: pid) ?? "?"
            return NewsAsset(
                id: pid,
                name: player?.fullDisplayName ?? "Player #\(pid)",
                position: pos,
                value: valuesStore.value(for: pid),
                isPick: false
            )
        }
        .sorted { $0.value > $1.value }
    }

    private static func pickAssets(
        from picks: [TradedPick]?,
        roster rid: Int,
        acquired: Bool,
        valuesStore: PlayerValuesStore,
        draftHistory: [DraftHistoryRecord] = [],
        slotByRosterIdBySeason: [String: [Int: Int]] = [:]
    ) -> [NewsAsset] {
        guard let picks else { return [] }
        return picks.compactMap { pick -> NewsAsset? in
            // A pick only counts if it actually changed owners in this deal.
            guard pick.ownerId != pick.previousOwnerId else { return nil }
            let owns = acquired ? pick.ownerId == rid : pick.previousOwnerId == rid
            guard owns else { return nil }

            // Resolve the pick's PHYSICAL draft slot.
            // TradedPick.rosterId = the ORIGINAL slot owner (not the slot
            // number). `slotByRosterIdBySeason` is derived from the draft's
            // authoritative `slot_to_roster_id`, keyed by season because the
            // slot order changes every year. We then match a draft-history
            // record by season/round/slot to find who the pick became.
            let originalSlot = slotByRosterIdBySeason[pick.season]?[pick.rosterId]
            let draftedPlayer = draftHistory.first { record in
                record.season == pick.season &&
                record.round == pick.round &&
                record.draftSlot == originalSlot
            }

            // Get the slot from draft history (if drafted) or the slot
            // mapping (if the draft order is set but not yet used).
            let slot: Int? = draftedPlayer?.draftSlot ?? originalSlot

            // For resolved picks, use the drafted player's current dynasty
            // value instead of the generic pick value. This makes historical
            // trade grades more accurate — a 2024 1st that became Caleb
            // Williams should be valued at Caleb Williams' current value,
            // not "2024 Mid 1st" which is now worthless.
            let value: Int
            let pickName = PickValuation.fantasyCalcName(season: pick.season, round: pick.round)
            if let playerId = draftedPlayer?.playerId {
                let playerValue = valuesStore.value(for: playerId)
                // Fall back to pick value if player not found (rare edge case)
                value = playerValue > 0 ? playerValue : valuesStore.pickValue(for: pickName)
            } else if let slot {
                // For future picks with known slot, use exact pick value
                value = valuesStore.exactPickValue(season: pick.season, round: pick.round, slot: slot)
            } else {
                value = valuesStore.pickValue(for: pickName)
            }

            #if DEBUG
            if value == 0 {
                print("[NewsBuilder] Pick '\(pickName)' has value=0, hasValues=\(valuesStore.hasValues), pickCount=\(valuesStore.allPickNames.count)")
            }
            #endif

            return NewsAsset(
                id: "pick-\(pick.season)-\(pick.round)-\(pick.rosterId)",
                name: PickValuation.displayName(season: pick.season, round: pick.round, slot: slot),
                position: "PICK",
                value: value,
                isPick: true,
                resolvedPlayerId: draftedPlayer?.playerId,
                resolvedPlayerName: draftedPlayer?.playerName,
                resolvedPlayerPosition: draftedPlayer?.playerPosition
            )
        }
        .sorted { $0.value > $1.value }
    }

    private static func faab(for rid: Int, transaction t: Transaction, type: NewsType) -> Int? {
        switch type {
        case .waiver:
            return t.settings?.waiverBid
        case .trade:
            guard let budget = t.waiverBudget, !budget.isEmpty else { return nil }
            let net = budget.reduce(0) { acc, transfer in
                acc + (transfer.receiver == rid ? transfer.amount : 0)
                    - (transfer.sender == rid ? transfer.amount : 0)
            }
            return net == 0 ? nil : net
        case .freeAgent:
            return nil
        }
    }

    private static func teamName(_ rid: Int, rosters: [Roster], users: [SleeperUser]) -> String {
        guard let roster = rosters.first(where: { $0.rosterId == rid }) else { return "Team \(rid)" }
        let user = users.first { $0.userId == roster.ownerId }
        return user?.teamName ?? user?.resolvedDisplayName ?? "Team \(rid)"
    }

    // MARK: Deterministic write-ups

    private static func headline(type: NewsType, sides: [NewsSide]) -> String {
        switch type {
        case .trade:
            guard sides.count == 2 else { return "Trade" }
            return "\(sides[0].teamName) ↔ \(sides[1].teamName)"
        case .waiver, .freeAgent:
            return sides.first?.teamName ?? type.label
        }
    }

    private static func summary(type: NewsType, sides: [NewsSide], grade: TradeGrade?) -> String {
        switch type {
        case .trade:
            return tradeSummary(sides: sides, grade: grade)

        case .waiver:
            return moveSummary(sides.first, verb: "claimed off waivers")

        case .freeAgent:
            return moveSummary(sides.first, verb: "signed")
        }
    }

    /// Multi-sentence trade write-up: each side's haul with its dynasty
    /// value, then a verdict that names the winner, the letter grade, and
    /// the point gap. Deterministic — no LLM.
    private static func tradeSummary(sides: [NewsSide], grade: TradeGrade?) -> String {
        guard sides.count == 2 else { return "" }

        var parts = sides.map { side -> String in
            var line = "\(side.teamName) landed \(list(side.acquired))"
            if side.acquiredValue > 0 {
                line += " (\(side.acquiredValue) in dynasty value)"
            }
            return line + "."
        }

        if let grade {
            if grade.isFair {
                parts.append("The board grades it a wash — both hauls land within \(percent(grade.percentGap)) on dynasty value, so each side walks away with a fair-market return.")
            } else if let winnerId = grade.winnerRosterId,
                      let winner = sides.first(where: { $0.rosterId == winnerId }),
                      let loser = sides.first(where: { $0.rosterId != winnerId }) {
                let letter = grade.letter(for: winnerId).rawValue
                parts.append("\(winner.teamName) wins this one (\(letter)), clearing \(loser.teamName) by \(grade.differential) points of dynasty value — a \(percent(grade.percentGap)) edge.")
            }
        }
        return parts.joined(separator: " ")
    }

    private static func moveSummary(_ side: NewsSide?, verb: String) -> String {
        guard let side else { return "" }
        var sentence = ""

        if !side.acquired.isEmpty {
            sentence = "\(side.teamName) \(verb) \(list(side.acquired))"
            if let faab = side.faab, faab > 0 {
                sentence += " for $\(faab) FAAB"
            }
            sentence += "."
        }

        if !side.relinquished.isEmpty {
            let dropped = list(side.relinquished)
            if sentence.isEmpty {
                sentence = "\(side.teamName) dropped \(dropped)."
            } else {
                sentence += " In the corresponding move, \(side.teamName) dropped \(dropped)."
            }
        }

        // Value-added context so a pickup isn't just a bare name — how
        // much dynasty value the move nets the roster.
        if side.acquiredValue > 0 || side.relinquishedValue > 0 {
            let net = side.netValue
            if net > 0 {
                sentence += " Adds \(net) in dynasty value to the roster."
            } else if net < 0 {
                sentence += " Sheds \(abs(net)) in dynasty value."
            } else {
                sentence += " A value-neutral roster shuffle."
            }
        }

        return sentence.isEmpty ? "\(side.teamName) made a roster move." : sentence
    }

    /// Oxford-comma join of asset display names.
    private static func list(_ assets: [NewsAsset]) -> String {
        let names = assets.map(\.name)
        switch names.count {
        case 0:  return "nothing"
        case 1:  return names[0]
        case 2:  return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head), and \(names.last ?? "")"
        }
    }

    private static func percent(_ p: Double) -> String {
        String(format: "%.0f%%", p * 100)
    }
}
