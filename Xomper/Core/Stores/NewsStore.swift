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

    // MARK: - Load

    /// Fetch + build the feed. Skips the network when the same league was
    /// loaded within the last 10 minutes and already has items, unless
    /// `forceRefresh` is set (pull-to-refresh).
    func load(
        leagueId: String,
        rosters: [Roster],
        users: [SleeperUser],
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore,
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
                valuesStore: valuesStore
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
        valuesStore: PlayerValuesStore
    ) -> NewsItem? {
        // Only surface completed, recognized moves.
        guard t.status == nil || t.status == "complete" else { return nil }
        guard let type = NewsType(sleeperType: t.type) else { return nil }

        let rosterIds = t.rosterIds ?? []
        guard !rosterIds.isEmpty else { return nil }

        let createdAt = Date(timeIntervalSince1970: Double(t.created ?? 0) / 1000.0)

        let sides: [NewsSide] = rosterIds.map { rid in
            let acquired = playerAssets(from: t.adds, roster: rid, playerStore: playerStore, valuesStore: valuesStore)
                + pickAssets(from: t.draftPicks, roster: rid, acquired: true, valuesStore: valuesStore)
            let relinquished = playerAssets(from: t.drops, roster: rid, playerStore: playerStore, valuesStore: valuesStore)
                + pickAssets(from: t.draftPicks, roster: rid, acquired: false, valuesStore: valuesStore)
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
        valuesStore: PlayerValuesStore
    ) -> [NewsAsset] {
        guard let picks else { return [] }
        return picks.compactMap { pick -> NewsAsset? in
            // A pick only counts if it actually changed owners in this deal.
            guard pick.ownerId != pick.previousOwnerId else { return nil }
            let owns = acquired ? pick.ownerId == rid : pick.previousOwnerId == rid
            guard owns else { return nil }
            return NewsAsset(
                id: "pick-\(pick.season)-\(pick.round)-\(pick.rosterId)",
                name: PickValuation.displayName(season: pick.season, round: pick.round),
                position: "PICK",
                value: valuesStore.pickValue(for: PickValuation.fantasyCalcName(season: pick.season, round: pick.round)),
                isPick: true
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
            guard sides.count == 2 else { return "" }
            var parts = sides.map { side -> String in
                "\(side.teamName) received \(list(side.acquired))."
            }
            if let grade {
                if grade.isFair {
                    parts.append("An even swap — both hauls land within \(percent(grade.percentGap)) on dynasty value.")
                } else if let winnerId = grade.winnerRosterId,
                          let winner = sides.first(where: { $0.rosterId == winnerId }) {
                    parts.append("\(winner.teamName) comes out ahead by \(percent(grade.percentGap)) in dynasty value.")
                }
            }
            return parts.joined(separator: " ")

        case .waiver:
            return moveSummary(sides.first, verb: "claimed off waivers")

        case .freeAgent:
            return moveSummary(sides.first, verb: "signed")
        }
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
