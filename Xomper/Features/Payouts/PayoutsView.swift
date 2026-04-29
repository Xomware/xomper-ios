import SwiftUI

/// Projects the signed-in user's current payout total based on the
/// hardcoded `LeaguePayouts.charlotteDynastyDefault` structure +
/// derived stats (champion bracket, season-high PF, weekly-high tally).
/// Categories that need data we don't yet aggregate (position MVPs)
/// render as "Coming soon" rows so the structure is visible.
struct PayoutsView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var playerPointsStore: PlayerPointsStore
    var authStore: AuthStore

    private let payouts: LeaguePayouts = .charlotteDynastyDefault

    @State private var selectedDrillDown: PayoutProjection?

    var body: some View {
        Group {
            if leagueStore.myLeagueRosters.isEmpty {
                LoadingView(message: "Loading league...")
            } else {
                content
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task(id: leagueStore.myLeague?.leagueId) {
            await ensureLoaded()
        }
        .refreshable {
            await reload()
        }
        .sheet(item: $selectedDrillDown) { projection in
            NavigationStack {
                PayoutDrillDownView(projection: projection, userId: authStore.sleeperUserId)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Content

    private var content: some View {
        let standings = computedStandings
        let projections = PayoutCalculator.project(
            payouts: payouts,
            standings: standings,
            matchupHistory: historyStore.matchupHistory,
            winnersBracket: leagueStore.winnersBracket,
            rosters: leagueStore.myLeagueRosters,
            playerStore: playerStore,
            playerPointsStore: playerPointsStore,
            userId: authStore.sleeperUserId
        )
        let projected = projections.map(\.projectedAmount).reduce(0, +)
        let upside = payouts.totalUpside

        return ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                summaryCard(projected: projected, upside: upside)

                ForEach(projections) { projection in
                    Button {
                        if projection.standings != nil {
                            selectedDrillDown = projection
                        }
                    } label: {
                        projectionRow(projection)
                    }
                    .buttonStyle(.pressableCard)
                    .disabled(projection.standings == nil)
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Summary card

    private func summaryCard(projected: Double, upside: Double) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Projected payout")
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(currency(projected))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()

            Text("Max possible: \(currency(upside))")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)

            Text("Based on current league data + the hardcoded payout structure. Tap any settled category for the full breakdown.")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
                .padding(.top, XomperTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Projection row

    private func projectionRow(_ projection: PayoutProjection) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(projection.category.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)

                if let reason = projection.unavailableReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .lineLimit(2)
                } else if let leader = projection.leader {
                    Text("Leader: \(leader.teamName)\(leader.displayValue.isEmpty ? "" : " · \(leader.displayValue)")")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(1)
                }

                placementBadge(projection)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(currency(projection.projectedAmount))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(projection.projectedAmount > 0 ? XomperColors.championGold : XomperColors.textMuted)
                    .monospacedDigit()

                Text("of \(currency(projection.category.maxAmount))")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)

                if projection.standings != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .opacity(projection.unavailableReason == nil ? 1.0 : 0.65)
    }

    @ViewBuilder
    private func placementBadge(_ projection: PayoutProjection) -> some View {
        switch projection.userPlacement {
        case .leading:
            badge("Leading", fg: XomperColors.bgDark, bg: XomperColors.championGold)
        case .tied(let other):
            badge("Tied with \(other)", fg: XomperColors.bgDark, bg: XomperColors.successGreen)
        case .behind(let by):
            if by.isEmpty {
                badge("Behind", fg: XomperColors.textSecondary, bg: XomperColors.surfaceLight.opacity(0.4))
            } else {
                badge("Behind by \(by)", fg: XomperColors.textSecondary, bg: XomperColors.surfaceLight.opacity(0.4))
            }
        case .won:
            badge("Won", fg: XomperColors.bgDark, bg: XomperColors.successGreen)
        case .pending:
            badge("Pending", fg: XomperColors.textMuted, bg: XomperColors.surfaceLight.opacity(0.3))
        case .notApplicable:
            EmptyView()
        }
    }

    private func badge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: - Data

    private var computedStandings: [StandingsTeam] {
        guard let league = leagueStore.myLeague else { return [] }
        return StandingsBuilder.buildStandings(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            league: league
        )
    }

    private func ensureLoaded() async {
        if leagueStore.leagueChain.isEmpty,
           let leagueId = leagueStore.myLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
        }
        if historyStore.matchupHistory.isEmpty, !leagueStore.leagueChain.isEmpty {
            await historyStore.loadMatchupHistory(chain: leagueStore.leagueChain)
        }
        if leagueStore.winnersBracket == nil,
           let leagueId = leagueStore.myLeague?.leagueId {
            await leagueStore.fetchBrackets(leagueId: leagueId)
        }
        // Per-player starter-points aggregation for position MVPs.
        // 14 weeks × ~12 matchups each — fits comfortably in a single
        // background pass; cached on the store so re-entering the view
        // doesn't re-fetch.
        if !playerPointsStore.hasData,
           let leagueId = leagueStore.myLeague?.leagueId {
            await playerPointsStore.loadRegularSeason(
                leagueId: leagueId,
                regularSeasonLastWeek: regularSeasonLastWeek
            )
        }
    }

    /// Final regular-season week. Derived from `playoff_week_start - 1`
    /// when available; falls back to 14 (the typical NFL fantasy
    /// regular season).
    private var regularSeasonLastWeek: Int {
        guard let value = leagueStore.myLeague?.settings?.additionalSettings?["playoff_week_start"] else {
            return 14
        }
        if let i = value.intValue { return max(i - 1, 1) }
        if let d = value.doubleValue { return max(Int(d) - 1, 1) }
        return 14
    }

    private func reload() async {
        historyStore.reset()
        await ensureLoaded()
    }

    private func currency(_ amount: Double) -> String {
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(amount))"
        }
        return String(format: "$%.0f", amount)
    }
}

// MARK: - Drill-down

private struct PayoutDrillDownView: View {
    let projection: PayoutProjection
    let userId: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                Text(projection.category.label)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)

                if let standings = projection.standings, !standings.isEmpty {
                    ForEach(Array(standings.enumerated()), id: \.offset) { idx, row in
                        drillRow(rank: idx + 1, row: row)
                    }
                } else {
                    Text("No data yet.")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
            .padding(XomperTheme.Spacing.md)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle(projection.category.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(XomperColors.championGold)
            }
        }
    }

    private func drillRow(rank: Int, row: PayoutProjection.StandingsRow) -> some View {
        let isMine = row.userId == userId
        return HStack {
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(rank == 1 ? XomperColors.championGold : XomperColors.textMuted)
                .frame(width: 24, alignment: .leading)

            Text(row.teamName)
                .font(.subheadline.weight(isMine ? .bold : .regular))
                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(row.displayValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .background(isMine ? XomperColors.championGold.opacity(0.12) : XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }
}
