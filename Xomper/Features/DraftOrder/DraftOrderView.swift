import SwiftUI

/// Draft Order screen. Three modes:
/// - `.live`: the actual commissioner-set order pulled from Sleeper
///   (`historyStore.upcomingDraft`). Default — answers "who's picking
///   when in this year's draft?" with the start time + 1-day-per-pick
///   pace.
/// - `.proposal`: the reverse-HPP rule proposal (non-playoff teams in
///   ascending season HPP, playoff teams at the back ordered by actual
///   playoff finish). What we'd switch to under the league rule
///   discussion from #57.
/// - `.mocks`: simulated rookie drafts driven by different personality
///   weightings (BPA, team-fit, wildcard…). Placeholder for now —
///   wired up once the mock engine lands.
struct DraftOrderView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var playerPointsStore: PlayerPointsStore
    var userStore: UserStore
    var nflStateStore: NflStateStore

    @State private var viewMode: DraftOrderViewMode = .live

    var body: some View {
        VStack(spacing: 0) {
            viewModeBar

            Group {
                switch viewMode {
                case .live:    liveContent
                case .proposal: proposalContent
                case .mocks:   mocksPlaceholder
                }
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task(id: leagueStore.myLeague?.leagueId) {
            await ensureProposalLoaded()
        }
        .task(id: viewMode) {
            if viewMode == .live { await ensureLiveLoaded() }
            if viewMode == .proposal { await ensureProposalLoaded() }
        }
        .refreshable {
            switch viewMode {
            case .live:    await ensureLiveLoaded()
            case .proposal: await ensureProposalLoaded()
            case .mocks:   break
            }
        }
    }

    // MARK: - View mode picker

    private var viewModeBar: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(DraftOrderViewMode.allCases) { mode in
                viewModeButton(mode)
            }
        }
        .padding(2)
        .background(XomperColors.surfaceLight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md + 2))
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
    }

    private func viewModeButton(_ mode: DraftOrderViewMode) -> some View {
        let isSelected = viewMode == mode
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) { viewMode = mode }
        } label: {
            Text(mode.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? XomperColors.bgDark : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isSelected ? XomperColors.championGold : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.pressableCard)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Live content

    private var liveContent: some View {
        Group {
            if historyStore.isLoadingUpcoming && historyStore.upcomingDraft == nil {
                LoadingView(message: "Loading \(nextDraftSeason) draft…")
            } else if let error = historyStore.upcomingError, historyStore.upcomingDraft == nil {
                ErrorView(message: error.localizedDescription) {
                    Task { await ensureLiveLoaded() }
                }
            } else if let draft = historyStore.upcomingDraft {
                liveDraftBody(draft: draft)
            } else {
                EmptyStateView(
                    icon: "calendar.badge.exclamationmark",
                    title: "\(nextDraftSeason) Draft Not Scheduled",
                    message: "The commissioner hasn't created next season's draft yet. Pull to refresh once it's set up."
                )
            }
        }
    }

    private func liveDraftBody(draft: Draft) -> some View {
        let teamsBySlot = liveTeamsBySlot(draft: draft)
        let slots = liveSlots(draft: draft, teamsBySlot: teamsBySlot)
        let rounds = max(draft.settings?.rounds ?? 5, 1)
        let totalPicks = slots.count * rounds
        let firstPick = liveStartDate(draft: draft)
        let myUserId = userStore.myUser?.userId

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                liveHeaderCard(draft: draft, totalPicks: totalPicks, firstPick: firstPick)

                sectionHeader("Round 1 order (\(slots.count) slots)")
                ForEach(slots, id: \.self) { slot in
                    let team = teamsBySlot[slot]
                    let isMine = team?.userId != nil && team?.userId == myUserId
                    liveRow(
                        slot: slot,
                        team: team,
                        isMine: isMine,
                        pickDate: pickDate(firstPick: firstPick, pickNo: slot)
                    )
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    private func liveHeaderCard(draft: Draft, totalPicks: Int, firstPick: Date?) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                Text("\(draft.season) rookie draft")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }

            if let firstPick {
                Text("Starts \(formatted(firstPick))")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            } else {
                Text("Slot order is locked. No start time set in Sleeper yet.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            if let firstPick, totalPicks > 0,
               let end = Calendar.current.date(byAdding: .day, value: totalPicks - 1, to: firstPick) {
                Text("Pace: ~1 day per pick → final pick around \(formattedShort(end))")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    private func liveRow(slot: Int, team: UpcomingDraftTeam?, isMine: Bool, pickDate: Date?) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Text("\(slot)")
                .font(.title3.weight(.bold))
                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textSecondary)
                .frame(width: 36, alignment: .leading)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(team?.teamName ?? "Slot \(slot)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                if let pickDate {
                    Text("Pick #\(slot) · ~\(formattedShort(pickDate))")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                } else {
                    Text("Pick #\(slot)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                }
            }

            Spacer()

            if isMine {
                Text("YOU")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(
                    isMine ? XomperColors.championGold.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private func liveTeamsBySlot(draft: Draft) -> [Int: UpcomingDraftTeam] {
        var byUser: [String: UpcomingDraftTeam] = [:]
        for user in historyStore.upcomingUsers {
            guard let userId = user.userId else { continue }
            byUser[userId] = UpcomingDraftTeam(
                userId: userId,
                teamName: user.teamName ?? user.resolvedDisplayName,
                avatarId: user.avatar
            )
        }
        var bySlot: [Int: UpcomingDraftTeam] = [:]
        if let order = draft.draftOrder {
            for (userId, slot) in order {
                if let team = byUser[userId] {
                    bySlot[slot] = team
                }
            }
        }
        return bySlot
    }

    private func liveSlots(draft: Draft, teamsBySlot: [Int: UpcomingDraftTeam]) -> [Int] {
        let count = draft.settings?.teams
            ?? max(teamsBySlot.keys.max() ?? 0, historyStore.upcomingRosters.count)
        return Array(1...max(count, 1))
    }

    private func liveStartDate(draft: Draft) -> Date? {
        guard let epochMillis = draft.startTime, epochMillis > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1000.0)
    }

    /// Each pick gets one calendar day. Pick #N is on `start + (N - 1)
    /// days`. Picks past slot count belong to round 2+ and aren't shown
    /// in this list, so we only use this for round-1 slot rows.
    private func pickDate(firstPick: Date?, pickNo: Int) -> Date? {
        guard let firstPick else { return nil }
        return Calendar.current.date(byAdding: .day, value: pickNo - 1, to: firstPick)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d 'at' h:mm a zzz"
        return f.string(from: date)
    }

    private func formattedShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private var nextDraftSeason: String {
        nflStateStore.currentSeason.isEmpty
            ? (leagueStore.myLeague?.season ?? "next")
            : nflStateStore.currentSeason
    }

    // MARK: - Proposal content

    private var proposalContent: some View {
        Group {
            if leagueStore.myLeagueRosters.isEmpty {
                LoadingView(message: "Loading league…")
            } else if !playerPointsStore.hasData {
                if playerPointsStore.isLoading {
                    LoadingView(message: "Computing perfect-lineup totals…")
                } else {
                    EmptyStateView(
                        icon: "list.number",
                        title: "Draft Order Pending",
                        message: "Per-week data not yet aggregated. Pull to refresh."
                    )
                }
            } else {
                proposalReady
            }
        }
    }

    private var proposalReady: some View {
        let projection = compute()

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                explainerCard

                if !projection.nonPlayoffOrder.isEmpty {
                    sectionHeader("Reverse-HPP order (picks 1–\(projection.nonPlayoffOrder.count))")
                    ForEach(Array(projection.nonPlayoffOrder.enumerated()), id: \.offset) { idx, entry in
                        row(rank: idx + 1, entry: entry, isPlayoff: false)
                    }
                }

                if !projection.playoffOrder.isEmpty {
                    sectionHeader(
                        "Playoff teams (picks "
                        + "\(projection.nonPlayoffOrder.count + 1)–"
                        + "\(projection.nonPlayoffOrder.count + projection.playoffOrder.count))"
                    )
                    ForEach(Array(projection.playoffOrder.enumerated()), id: \.offset) { idx, entry in
                        row(
                            rank: projection.nonPlayoffOrder.count + idx + 1,
                            entry: entry,
                            isPlayoff: true
                        )
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text("PROPOSAL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                Text("Reverse-HPP draft order")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }

            Text("This is a *proposed* rule, not in effect yet. The actual order set by the commissioner lives on the Live tab.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)

            Divider()
                .overlay(XomperColors.surfaceLight.opacity(0.4))
                .padding(.vertical, 2)

            Text("How it would work")
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.textSecondary)

            Text("Non-playoff teams pick in ascending order of season Highest Possible Points (perfect-lineup score). Playoff teams pick at the back, ordered by playoff finish.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)

            Text("HPP credits a team for the points they could have scored if they'd started their best lineup each week. Set bad lineups → high HPP / low wins → late pick. Maximized starts but unlucky → low HPP → early pick.")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(XomperColors.textMuted)
            .padding(.top, XomperTheme.Spacing.sm)
    }

    private func row(rank: Int, entry: DraftOrderProjection.Entry, isPlayoff: Bool) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Text("\(rank)")
                .font(.title3.weight(.bold))
                .foregroundStyle(rank == 1 ? XomperColors.championGold : XomperColors.textSecondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: XomperTheme.Spacing.sm) {
                    Text(entry.recordLabel)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                    Text(entry.actualPFLabel)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                    if isPlayoff {
                        Text(playoffBadgeText(finish: entry.playoffFinish))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(XomperColors.bgDark)
                            .padding(.horizontal, XomperTheme.Spacing.xs)
                            .background(playoffBadgeColor(finish: entry.playoffFinish))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", entry.seasonHPP))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()
                Text("season HPP")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    private func playoffBadgeText(finish: Int?) -> String {
        switch finish {
        case 1: return "CHAMPION"
        case 2: return "RUNNER-UP"
        case 3: return "3RD"
        case 4: return "4TH"
        case 5: return "5TH"
        case 6: return "6TH"
        case .some(let n): return "\(n)TH"
        case .none: return "PLAYOFFS"
        }
    }

    private func playoffBadgeColor(finish: Int?) -> Color {
        switch finish {
        case 1: return XomperColors.championGold
        case 2, 3: return XomperColors.successGreen
        default: return XomperColors.successGreen.opacity(0.7)
        }
    }

    // MARK: - Mocks placeholder

    private var mocksPlaceholder: some View {
        EmptyStateView(
            icon: "wand.and.stars",
            title: "Mock Drafts Coming Soon",
            message: "A 5-round rookie mock driven by team-need scoring + multiple draft personalities. Lands in the next update."
        )
    }

    // MARK: - Compute (proposal)

    private func compute() -> DraftOrderProjection {
        DraftOrderProjection.compute(
            leagueStore: leagueStore,
            historyStore: historyStore,
            playerStore: playerStore,
            playerPointsStore: playerPointsStore,
            regularSeasonLastWeek: regularSeasonLastWeek
        )
    }

    // MARK: - Data loading

    private func ensureProposalLoaded() async {
        if !playerPointsStore.hasData,
           let leagueId = leagueStore.myLeague?.leagueId {
            await playerPointsStore.loadRegularSeason(
                leagueId: leagueId,
                regularSeasonLastWeek: regularSeasonLastWeek
            )
        }
    }

    private func ensureLiveLoaded() async {
        guard let userId = userStore.myUser?.userId else { return }
        let homeName = leagueStore.resolvedHomeLeagueName
        let season = nextDraftSeason
        await historyStore.loadUpcomingDraft(
            season: season,
            homeLeagueName: homeName,
            userId: userId
        )
    }

    private var regularSeasonLastWeek: Int {
        guard let value = leagueStore.myLeague?.settings?.additionalSettings?["playoff_week_start"] else {
            return 14
        }
        if let i = value.intValue { return max(i - 1, 1) }
        if let d = value.doubleValue { return max(Int(d) - 1, 1) }
        return 14
    }
}

// MARK: - View mode

enum DraftOrderViewMode: String, CaseIterable, Identifiable {
    case live, proposal, mocks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live:     return "Live"
        case .proposal: return "Proposal"
        case .mocks:    return "Mocks"
        }
    }
}

// MARK: - Projection

struct DraftOrderProjection: Sendable {
    let nonPlayoffOrder: [Entry]
    let playoffOrder: [Entry]

    static let empty = DraftOrderProjection(nonPlayoffOrder: [], playoffOrder: [])

    struct Entry: Sendable, Hashable {
        let rosterId: Int
        let teamName: String
        let recordLabel: String
        let actualPFLabel: String
        let actualPF: Double
        let seasonHPP: Double
        let leagueRank: Int
        /// Final playoff finish (1 = champion, 6 = first-round-out). `nil`
        /// means we couldn't resolve a placement — either the team was
        /// non-playoff, or playoff games haven't been recorded yet.
        let playoffFinish: Int?
    }

    @MainActor
    static func compute(
        leagueStore: LeagueStore,
        historyStore: HistoryStore,
        playerStore: PlayerStore,
        playerPointsStore: PlayerPointsStore,
        regularSeasonLastWeek: Int
    ) -> DraftOrderProjection {
        guard let league = leagueStore.myLeague else { return .empty }
        let standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            league: league
        )

        let rosterPositions = league.rosterPositions ?? []
        let playoffTeams = league.settings?.playoffTeams ?? 6
        let finishByRoster = playoffFinishMap(
            history: historyStore.matchups(forSeason: league.season)
        )

        let entries: [Entry] = standings.map { team in
            let hpp = HighestPossibleCalculator.seasonHPP(
                rosterId: team.rosterId,
                rosterPositions: rosterPositions,
                playerPointsStore: playerPointsStore,
                playerStore: playerStore,
                regularSeasonLastWeek: regularSeasonLastWeek
            )
            return Entry(
                rosterId: team.rosterId,
                teamName: team.teamName,
                recordLabel: "\(team.wins)-\(team.losses)\(team.ties > 0 ? "-\(team.ties)" : "")",
                actualPFLabel: String(format: "%.1f PF", team.fpts),
                actualPF: team.fpts,
                seasonHPP: hpp,
                leagueRank: team.leagueRank,
                playoffFinish: finishByRoster[team.rosterId]
            )
        }

        // Standings is already sorted by wins-DESC then PF-DESC. Top
        // playoff_teams qualify; rest go to non-playoff.
        let playoffEntries = Array(entries.prefix(playoffTeams))
        let nonPlayoff = Array(entries.dropFirst(playoffTeams))
            .sorted(by: { $0.seasonHPP < $1.seasonHPP })  // ascending HPP

        // Playoff teams pick at the back, ordered by actual playoff
        // finish (worst finish first → earlier pick; champion picks
        // last). Sleeper carries the placement-deciding match on
        // `playoffPlacement`. Teams without a resolved finish (mid-
        // season, or a first-round-out team in a bracket without
        // consolation games) fall back to regular-season seed: their
        // standings position decides who's worst. Same-finish ties
        // also break by regular-season seed (lower seed = worse →
        // earlier pick).
        let playoffOrder = playoffEntries.sorted { lhs, rhs in
            let l = lhs.playoffFinish ?? Int.max
            let r = rhs.playoffFinish ?? Int.max
            if l != r { return l > r }
            return lhs.leagueRank > rhs.leagueRank
        }

        return DraftOrderProjection(
            nonPlayoffOrder: nonPlayoff,
            playoffOrder: playoffOrder
        )
    }

    /// Build rosterId → final playoff finish (1 = champion … N = worst
    /// in-bracket finish) from Sleeper bracket-derived matchup records.
    ///
    /// Sleeper attaches `placement` to the match that decides a finish:
    /// 1 = championship (winner = 1st, loser = 2nd), 3 = 3rd-place game
    /// (winner = 3rd, loser = 4th), 5/7/9/11 = lower seeding matches.
    /// Only the placement-bearing match per team is needed; the team's
    /// best (lowest-numbered) resolved finish wins.
    private static func playoffFinishMap(
        history: [MatchupHistoryRecord]
    ) -> [Int: Int] {
        var byRoster: [Int: Int] = [:]
        for record in history {
            guard let placement = record.playoffPlacement else { continue }
            let winnerFinish = placement
            let loserFinish = placement + 1
            let winner = record.winnerRosterId
            let teamA = record.teamARosterId
            let teamB = record.teamBRosterId
            let aFinish = winner == teamA ? winnerFinish : loserFinish
            let bFinish = winner == teamB ? winnerFinish : loserFinish
            update(&byRoster, teamA, finish: aFinish)
            update(&byRoster, teamB, finish: bFinish)
        }
        return byRoster
    }

    private static func update(_ map: inout [Int: Int], _ rosterId: Int, finish: Int) {
        if let existing = map[rosterId] {
            map[rosterId] = min(existing, finish)
        } else {
            map[rosterId] = finish
        }
    }
}
