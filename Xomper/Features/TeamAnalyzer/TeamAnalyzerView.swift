import SwiftUI

/// Hexagon-chart team analyzer. Two tabs:
/// - **Compare** — your team vs another team in the league, hex chart
///   + per-position breakdown, with the league average underlaid as a
///   muted reference polygon. Opponent picker is a dropdown menu so
///   12 team names don't have to scroll horizontally.
/// - **League** — every team ranked by total roster value, with
///   per-position bars normalized against the league max plus a
///   league-average row at the top.
///
/// Trade Analyzer (build-a-trade UI with FantasyCalc pick values + a
/// value-balanced suggester) is filed as a separate feature; the
/// scaffolding here is prep for that page.
///
/// Sources:
/// - `PlayerValuesStore` — FantasyCalc dynasty superflex values
/// - `LeagueStore.myLeagueRosters / myLeagueUsers` — anchored to home
/// - `PlayerStore.player(for:)` — position resolution
struct TeamAnalyzerView: View {
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var authStore: AuthStore
    var valuesStore: PlayerValuesStore

    @State private var activeTab: AnalyzerTab = .compare
    @State private var comparisonRosterId: Int?

    // Trade-builder state. Lives at the parent so the proposal
    // survives tab switches; the user can hop to Compare / League
    // mid-build and come back to the same trade.
    @State private var tradePartnerRosterId: Int?
    @State private var tradeSideAPlayerIds: [String] = []
    @State private var tradeSideBPlayerIds: [String] = []
    @State private var tradeSideAPickNames: [String] = []
    @State private var tradeSideBPickNames: [String] = []
    @State private var showSidePicker: TradeSidePickerContext?

    var body: some View {
        Group {
            if !valuesStore.hasValues && valuesStore.isLoading {
                LoadingView(message: "Fetching player values...")
            } else if let error = valuesStore.error, !valuesStore.hasValues {
                ErrorView(message: error.localizedDescription) {
                    Task { await valuesStore.loadValues(forceRefresh: true) }
                }
            } else if !valuesStore.hasValues {
                EmptyStateView(
                    icon: "chart.dots.scatter",
                    title: "Values Not Loaded",
                    message: "Pull to refresh to load dynasty values."
                )
            } else if leagueStore.myLeagueRosters.isEmpty {
                LoadingView(message: "Loading league...")
            } else {
                content
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task {
            await valuesStore.loadValues()
        }
        .refreshable {
            await valuesStore.loadValues(forceRefresh: true)
        }
    }

    // MARK: - Content

    private var content: some View {
        let analyses = TeamAnalysisBuilder.build(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            valuesStore: valuesStore
        )
        let myAnalysis = primaryAnalysis(in: analyses)
        let comparison = analyses.first { $0.rosterId == comparisonRosterId }
        let axisMaxes = TeamAnalysisBuilder.axisMaxes(analyses)
        let leagueAverages = TeamAnalysisBuilder.leagueAverageAxes(analyses)

        return VStack(spacing: 0) {
            tabBar

            switch activeTab {
            case .compare:
                compareTab(
                    my: myAnalysis,
                    comparison: comparison,
                    analyses: analyses,
                    axisMaxes: axisMaxes,
                    leagueAverages: leagueAverages
                )
            case .league:
                leagueTab(
                    analyses: analyses,
                    axisMaxes: axisMaxes,
                    leagueAverages: leagueAverages,
                    myUserId: authStore.sleeperUserId
                )
            case .trade:
                tradeTab(
                    my: myAnalysis,
                    analyses: analyses
                )
            }
        }
    }

    private func primaryAnalysis(in analyses: [TeamAnalysis]) -> TeamAnalysis? {
        guard let userId = authStore.sleeperUserId else { return analyses.first }
        return analyses.first { $0.userId == userId } ?? analyses.first
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AnalyzerTab.allCases, id: \.self) { tab in
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(XomperTheme.defaultAnimation) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.title)
                            .font(.subheadline.weight(activeTab == tab ? .bold : .regular))
                            .foregroundStyle(activeTab == tab ? XomperColors.championGold : XomperColors.textSecondary)
                        Rectangle()
                            .fill(activeTab == tab ? XomperColors.championGold : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressableCard)
                .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
            }
        }
        .padding(.top, XomperTheme.Spacing.xs)
        .background(XomperColors.bgDark)
    }

    // MARK: - Compare tab

    @ViewBuilder
    private func compareTab(
        my: TeamAnalysis?,
        comparison: TeamAnalysis?,
        analyses: [TeamAnalysis],
        axisMaxes: [String: Int],
        leagueAverages: [TeamAnalysis.HexAxis]
    ) -> some View {
        if let my {
            ScrollView {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.lg) {
                    headerCard(my: my, opp: comparison)

                    HexagonChartView(
                        primary: my.hexAxes,
                        comparison: comparison?.hexAxes,
                        leagueAverage: leagueAverages,
                        axisMaxes: axisMaxes
                    )
                    .padding(.horizontal, XomperTheme.Spacing.md)

                    legend(my: my, opp: comparison)

                    opponentDropdown(
                        analyses: analyses,
                        excludingRosterId: my.rosterId
                    )

                    breakdownGrid(
                        my: my,
                        opp: comparison,
                        averages: leagueAverages,
                        maxes: axisMaxes
                    )
                }
                .padding(.bottom, XomperTheme.Spacing.xl)
            }
        } else {
            EmptyStateView(
                icon: "person.crop.square",
                title: "Team Not Found",
                message: "Could not resolve your team in this league."
            )
        }
    }

    // MARK: - Header

    private func headerCard(my: TeamAnalysis, opp: TeamAnalysis?) -> some View {
        Text(opp == nil
            ? "Your roster, valued by position group. League average shown as a dashed reference polygon."
            : "Comparing your team vs \(opp!.teamName). League average underlaid as a dashed reference."
        )
        .font(.subheadline)
        .foregroundStyle(XomperColors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Legend

    private func legend(my: TeamAnalysis, opp: TeamAnalysis?) -> some View {
        HStack(spacing: XomperTheme.Spacing.lg) {
            legendChip(color: XomperColors.championGold, label: my.teamName)
            if let opp {
                legendChip(color: .cyan, label: opp.teamName)
            }
            legendChip(color: .gray, label: "League avg", dashed: true)
            Spacer()
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func legendChip(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Circle()
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: dashed ? 1.5 : 0,
                        dash: dashed ? [3, 2] : []
                    )
                )
                .background(Circle().fill(dashed ? Color.clear : color))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Opponent dropdown

    /// Replaces the previous horizontal-scroll chip row — with 12
    /// teams, that strip required awkward swiping. A native `Menu`
    /// fits all teams in one tap, sorted by total roster value
    /// descending so strongest comparisons surface first.
    private func opponentDropdown(analyses: [TeamAnalysis], excludingRosterId: Int) -> some View {
        let candidates = analyses
            .filter { $0.rosterId != excludingRosterId }
            .sorted { $0.totalValue > $1.totalValue }
        let selectedName = candidates.first { $0.rosterId == comparisonRosterId }?.teamName

        return HStack(spacing: XomperTheme.Spacing.sm) {
            Text("Compare against")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textSecondary)

            Menu {
                Button("None") { comparisonRosterId = nil }
                Divider()
                ForEach(candidates, id: \.rosterId) { team in
                    Button {
                        comparisonRosterId = team.rosterId
                    } label: {
                        HStack {
                            Text(team.teamName)
                            Spacer()
                            Text("\(team.totalValue)")
                                .monospacedDigit()
                        }
                    }
                }
            } label: {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Text(selectedName ?? "Select team")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedName == nil ? XomperColors.textSecondary : XomperColors.bgDark)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedName == nil ? XomperColors.textSecondary : XomperColors.bgDark)
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: 36)
                .background(selectedName == nil ? XomperColors.surfaceLight.opacity(0.4) : Color.cyan)
                .clipShape(Capsule())
            }
            .accessibilityLabel(selectedName.map { "Comparing against \($0)" } ?? "Pick comparison team")

            Spacer()
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Breakdown grid

    private func breakdownGrid(
        my: TeamAnalysis,
        opp: TeamAnalysis?,
        averages: [TeamAnalysis.HexAxis],
        maxes: [String: Int]
    ) -> some View {
        VStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(Array(my.hexAxes.enumerated()), id: \.offset) { idx, axis in
                let oppValue = opp?.hexAxes[idx].value
                let avgValue = idx < averages.count ? averages[idx].value : 0
                breakdownRow(
                    label: axis.label,
                    myValue: axis.value,
                    oppValue: oppValue,
                    avgValue: avgValue,
                    leagueMax: maxes[axis.label] ?? axis.value
                )
            }
            Divider().background(XomperColors.surfaceLight.opacity(0.4))
            HStack {
                Text("Total roster value")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textSecondary)
                Spacer()
                Text("\(my.totalValue)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()
                if let opp {
                    Text("vs \(opp.totalValue)")
                        .font(.subheadline)
                        .foregroundStyle(.cyan)
                        .monospacedDigit()
                }
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func breakdownRow(
        label: String,
        myValue: Int,
        oppValue: Int?,
        avgValue: Int,
        leagueMax: Int
    ) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .frame(width: 60, alignment: .leading)

            ProgressView(
                value: leagueMax > 0 ? Double(myValue) / Double(leagueMax) : 0
            )
            .tint(XomperColors.championGold)
            .frame(maxWidth: .infinity)

            Text("\(myValue)")
                .font(.caption.weight(.bold))
                .foregroundStyle(deltaColor(myValue: myValue, avgValue: avgValue))
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)

            if let oppValue {
                Text("\(oppValue)")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("\(avgValue)")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    /// Color my-team's value gold when above league average and red
    /// when significantly below — a glance-readable health check on
    /// position depth without needing to do the math.
    private func deltaColor(myValue: Int, avgValue: Int) -> Color {
        guard avgValue > 0 else { return XomperColors.textPrimary }
        let ratio = Double(myValue) / Double(avgValue)
        if ratio >= 1.05 { return XomperColors.championGold }
        if ratio <= 0.85 { return XomperColors.errorRed }
        return XomperColors.textPrimary
    }

    // MARK: - League tab

    private func leagueTab(
        analyses: [TeamAnalysis],
        axisMaxes: [String: Int],
        leagueAverages: [TeamAnalysis.HexAxis],
        myUserId: String?
    ) -> some View {
        let ranked = analyses.sorted { $0.totalValue > $1.totalValue }
        let totalAvg = ranked.reduce(0) { $0 + $1.totalValue } / max(ranked.count, 1)

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                leagueAveragesCard(averages: leagueAverages, totalAvg: totalAvg)

                Text("Teams · ranked by total value")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(XomperColors.textMuted)
                    .padding(.horizontal, XomperTheme.Spacing.md)
                    .padding(.top, XomperTheme.Spacing.sm)

                ForEach(Array(ranked.enumerated()), id: \.offset) { idx, team in
                    let isMine = team.userId == myUserId
                    leagueTeamRow(
                        rank: idx + 1,
                        team: team,
                        isMine: isMine,
                        averages: leagueAverages,
                        maxes: axisMaxes
                    )
                }
            }
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
    }

    private func leagueAveragesCard(
        averages: [TeamAnalysis.HexAxis],
        totalAvg: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("League averages")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)

            HStack(spacing: XomperTheme.Spacing.md) {
                ForEach(averages, id: \.label) { axis in
                    VStack(spacing: 2) {
                        Text(axis.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(XomperColors.textMuted)
                        Text("\(axis.value)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(XomperColors.textPrimary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider().background(XomperColors.surfaceLight.opacity(0.4))

            HStack {
                Text("Average total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textSecondary)
                Spacer()
                Text("\(totalAvg)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()
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
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func leagueTeamRow(
        rank: Int,
        team: TeamAnalysis,
        isMine: Bool,
        averages: [TeamAnalysis.HexAxis],
        maxes: [String: Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Text("\(rank)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(rank == 1 ? XomperColors.championGold : XomperColors.textSecondary)
                    .frame(width: 28, alignment: .leading)
                    .monospacedDigit()

                Text(team.teamName)
                    .font(.subheadline.weight(isMine ? .bold : .semibold))
                    .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textPrimary)
                    .lineLimit(1)

                if isMine {
                    Text("YOU")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, XomperTheme.Spacing.xs)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                }

                Spacer()

                Text("\(team.totalValue)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .monospacedDigit()
            }

            HStack(spacing: XomperTheme.Spacing.xs) {
                ForEach(Array(team.hexAxes.enumerated()), id: \.offset) { idx, axis in
                    let avg = idx < averages.count ? averages[idx].value : 0
                    let max = maxes[axis.label] ?? axis.value
                    leagueTeamAxisCell(axis: axis, avg: avg, leagueMax: max)
                }
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
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func leagueTeamAxisCell(
        axis: TeamAnalysis.HexAxis,
        avg: Int,
        leagueMax: Int
    ) -> some View {
        let fill = leagueMax > 0 ? CGFloat(axis.value) / CGFloat(leagueMax) : 0
        return VStack(spacing: 2) {
            Text(axis.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(XomperColors.surfaceLight.opacity(0.4))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(deltaColor(myValue: axis.value, avgValue: avg))
                        .frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 6)
            Text("\(axis.value)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(deltaColor(myValue: axis.value, avgValue: avg))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trade tab

extension TeamAnalyzerView {

    @ViewBuilder
    fileprivate func tradeTab(
        my: TeamAnalysis?,
        analyses: [TeamAnalysis]
    ) -> some View {
        if let my {
            tradeBuilder(my: my, analyses: analyses)
                .sheet(item: $showSidePicker) { context in
                    NavigationStack {
                        tradePlayerPicker(
                            context: context,
                            my: my,
                            analyses: analyses
                        )
                    }
                    .presentationDetents([.large])
                }
        } else {
            EmptyStateView(
                icon: "person.crop.square",
                title: "Team Not Found",
                message: "Could not resolve your team in this league."
            )
        }
    }

    private func tradeBuilder(
        my: TeamAnalysis,
        analyses: [TeamAnalysis]
    ) -> some View {
        let partner = analyses.first { $0.rosterId == tradePartnerRosterId }
        let trade = currentTrade(my: my, partner: partner)
        let evaluation = TradeEvaluator.evaluate(trade, valuesStore: valuesStore)
        let suggestions = TradeEvaluator.suggestBalance(
            for: trade,
            evaluation: evaluation,
            rosters: leagueStore.myLeagueRosters,
            valuesStore: valuesStore,
            playerStore: playerStore
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                tradeExplainer

                tradePartnerPicker(my: my, analyses: analyses)

                if partner != nil {
                    tradeEvaluationStrip(evaluation: evaluation)

                    tradeSideCard(
                        sideLabel: "You give",
                        teamName: my.teamName,
                        playerIds: tradeSideAPlayerIds,
                        pickNames: tradeSideAPickNames,
                        sideValue: evaluation.sideAValue,
                        addPlayerAction: {
                            showSidePicker = TradeSidePickerContext(
                                side: .a,
                                kind: .player,
                                rosterId: my.rosterId,
                                teamName: my.teamName
                            )
                        },
                        addPickAction: {
                            showSidePicker = TradeSidePickerContext(
                                side: .a,
                                kind: .pick,
                                rosterId: my.rosterId,
                                teamName: my.teamName
                            )
                        },
                        removePlayerAction: { pid in
                            tradeSideAPlayerIds.removeAll { $0 == pid }
                        },
                        removePickAction: { name in
                            tradeSideAPickNames.removeAll { $0 == name }
                        }
                    )

                    if let partner {
                        tradeSideCard(
                            sideLabel: "You receive",
                            teamName: partner.teamName,
                            playerIds: tradeSideBPlayerIds,
                            pickNames: tradeSideBPickNames,
                            sideValue: evaluation.sideBValue,
                            addPlayerAction: {
                                showSidePicker = TradeSidePickerContext(
                                    side: .b,
                                    kind: .player,
                                    rosterId: partner.rosterId,
                                    teamName: partner.teamName
                                )
                            },
                            addPickAction: {
                                showSidePicker = TradeSidePickerContext(
                                    side: .b,
                                    kind: .pick,
                                    rosterId: partner.rosterId,
                                    teamName: partner.teamName
                                )
                            },
                            removePlayerAction: { pid in
                                tradeSideBPlayerIds.removeAll { $0 == pid }
                            },
                            removePickAction: { name in
                                tradeSideBPickNames.removeAll { $0 == name }
                            }
                        )
                    }

                    if !suggestions.isEmpty {
                        balanceSuggestionsCard(
                            suggestions: suggestions,
                            evaluation: evaluation
                        )
                    }

                    if !trade.isEmpty {
                        Button(role: .destructive) {
                            tradeSideAPlayerIds = []
                            tradeSideBPlayerIds = []
                            tradeSideAPickNames = []
                            tradeSideBPickNames = []
                        } label: {
                            Text("Clear trade")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(XomperColors.errorRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, XomperTheme.Spacing.sm)
                        }
                        .buttonStyle(.pressableCard)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                    }
                }

                // Recommended trades (independent of partner selection
                // — these are league-wide suggestions for fixing weak
                // positions; tap one to load it into the builder).
                recommendedTradesSection(myAnalysis: my, analyses: analyses)
            }
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
    }

    private func currentTrade(my: TeamAnalysis, partner: TeamAnalysis?) -> ProposedTrade {
        ProposedTrade(
            sideA: TradeSide(
                rosterId: my.rosterId,
                teamName: my.teamName,
                playerIds: tradeSideAPlayerIds,
                pickNames: tradeSideAPickNames
            ),
            sideB: TradeSide(
                rosterId: partner?.rosterId ?? 0,
                teamName: partner?.teamName ?? "",
                playerIds: tradeSideBPlayerIds,
                pickNames: tradeSideBPickNames
            )
        )
    }

    private var tradeExplainer: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(XomperColors.championGold)
                Text("Trade analyzer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }
            Text("Pick a partner, drop in players or draft picks from each side. Live FantasyCalc value totals + verdict pill update on every change. Uneven trades surface balance suggestions; the recommended-trades section below auto-finds fair-value upgrades to your weakest position.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func tradePartnerPicker(my: TeamAnalysis, analyses: [TeamAnalysis]) -> some View {
        let candidates = analyses
            .filter { $0.rosterId != my.rosterId }
            .sorted { $0.totalValue > $1.totalValue }
        let selectedName = candidates.first { $0.rosterId == tradePartnerRosterId }?.teamName

        return HStack(spacing: XomperTheme.Spacing.sm) {
            Text("Trade partner")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textSecondary)

            Menu {
                Button("None") {
                    tradePartnerRosterId = nil
                    tradeSideBPlayerIds = []
                }
                Divider()
                ForEach(candidates, id: \.rosterId) { team in
                    Button {
                        if tradePartnerRosterId != team.rosterId {
                            tradeSideBPlayerIds = []
                        }
                        tradePartnerRosterId = team.rosterId
                    } label: {
                        HStack {
                            Text(team.teamName)
                            Spacer()
                            Text("\(team.totalValue)")
                                .monospacedDigit()
                        }
                    }
                }
            } label: {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Text(selectedName ?? "Pick partner")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedName == nil ? XomperColors.textSecondary : XomperColors.bgDark)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedName == nil ? XomperColors.textSecondary : XomperColors.bgDark)
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: 36)
                .background(selectedName == nil ? XomperColors.surfaceLight.opacity(0.4) : Color.cyan)
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func tradeEvaluationStrip(evaluation: TradeEvaluation) -> some View {
        let pillColor: Color = {
            switch evaluation.verdict {
            case .empty:    return XomperColors.surfaceLight.opacity(0.4)
            case .fair:     return XomperColors.successGreen
            case .sideAWins, .sideBWins: return XomperColors.errorRed.opacity(0.85)
            }
        }()

        return VStack(spacing: XomperTheme.Spacing.sm) {
            HStack {
                tradeValueColumn(label: "You give", value: evaluation.sideAValue)
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(XomperColors.textMuted)
                Spacer()
                tradeValueColumn(label: "You receive", value: evaluation.sideBValue)
            }

            Text(evaluation.verdict.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(evaluation.verdict.isFair ? XomperColors.bgDark : .white)
                .textCase(.uppercase)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .background(pillColor)
                .clipShape(Capsule())
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func tradeValueColumn(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
        }
    }

    private func tradeSideCard(
        sideLabel: String,
        teamName: String,
        playerIds: [String],
        pickNames: [String],
        sideValue: Int,
        addPlayerAction: @escaping () -> Void,
        addPickAction: @escaping () -> Void,
        removePlayerAction: @escaping (String) -> Void,
        removePickAction: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sideLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(XomperColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(teamName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(sideValue)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()
            }

            if playerIds.isEmpty && pickNames.isEmpty {
                Text("No players or picks added yet.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .padding(.vertical, XomperTheme.Spacing.xs)
            } else {
                ForEach(playerIds, id: \.self) { pid in
                    tradePlayerRow(pid: pid, removeAction: { removePlayerAction(pid) })
                }
                ForEach(pickNames, id: \.self) { name in
                    tradePickRow(name: name, removeAction: { removePickAction(name) })
                }
            }

            HStack(spacing: XomperTheme.Spacing.xs) {
                Button(action: addPlayerAction) {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text("Player")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.md)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .frame(minHeight: 36)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)

                Button(action: addPickAction) {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Image(systemName: "plus.circle")
                        Text("Pick")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                    .padding(.horizontal, XomperTheme.Spacing.md)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .frame(minHeight: 36)
                    .background(XomperColors.surfaceLight.opacity(0.4))
                    .overlay(
                        Capsule().strokeBorder(XomperColors.championGold.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func tradePickRow(name: String, removeAction: @escaping () -> Void) -> some View {
        let value = valuesStore.pickValue(for: name)
        return HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "ticket.fill")
                .foregroundStyle(XomperColors.championGold)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
            Text("PICK")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(XomperColors.textMuted)
            }
            .buttonStyle(.pressableCard)
        }
        .padding(.vertical, 2)
    }

    private func tradePlayerRow(pid: String, removeAction: @escaping () -> Void) -> some View {
        let player = playerStore.player(for: pid)
        let value = valuesStore.value(for: pid)
        return HStack(spacing: XomperTheme.Spacing.sm) {
            Text(player?.fullDisplayName ?? "Player #\(pid)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
            Text(player?.displayPosition ?? "")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(XomperColors.textMuted)
            }
            .buttonStyle(.pressableCard)
        }
        .padding(.vertical, 2)
    }

    private func balanceSuggestionsCard(
        suggestions: [SuggestedAddOn],
        evaluation: TradeEvaluation
    ) -> some View {
        let lighterLabel: String = {
            switch evaluation.verdict {
            case .sideAWins: return "You receive"
            case .sideBWins: return "You give"
            default: return ""
            }
        }()

        return VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Balance suggestions")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Text("Add one of these to \(lighterLabel.lowercased()) to bring the trade within 5%.")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }

            ForEach(suggestions) { suggestion in
                Button {
                    switch evaluation.verdict {
                    case .sideAWins:
                        if !tradeSideBPlayerIds.contains(suggestion.playerId) {
                            tradeSideBPlayerIds.append(suggestion.playerId)
                        }
                    case .sideBWins:
                        if !tradeSideAPlayerIds.contains(suggestion.playerId) {
                            tradeSideAPlayerIds.append(suggestion.playerId)
                        }
                    default:
                        break
                    }
                } label: {
                    HStack(spacing: XomperTheme.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.playerName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(XomperColors.textPrimary)
                                .lineLimit(1)
                            Text(suggestion.position)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(XomperColors.textSecondary)
                        }
                        Spacer()
                        Text("\(suggestion.value)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(XomperColors.championGold)
                            .monospacedDigit()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(XomperColors.championGold)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.pressableCard)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Player picker sheet

    @ViewBuilder
    fileprivate func tradePlayerPicker(
        context: TradeSidePickerContext,
        my: TeamAnalysis,
        analyses: [TeamAnalysis]
    ) -> some View {
        switch context.kind {
        case .player:
            tradePlayerSelectionList(context: context)
        case .pick:
            tradePickSelectionList(context: context)
        }
    }

    @ViewBuilder
    private func tradePlayerSelectionList(context: TradeSidePickerContext) -> some View {
        let alreadyPicked: Set<String> = {
            switch context.side {
            case .a: return Set(tradeSideAPlayerIds)
            case .b: return Set(tradeSideBPlayerIds)
            }
        }()
        let roster = leagueStore.myLeagueRosters.first { $0.rosterId == context.rosterId }
        let players: [TradePickerEntry] = (roster?.players ?? [])
            .compactMap { pid in
                guard !alreadyPicked.contains(pid) else { return nil }
                let value = valuesStore.value(for: pid)
                guard value > 0 else { return nil }
                let player = playerStore.player(for: pid)
                return TradePickerEntry(
                    playerId: pid,
                    name: player?.fullDisplayName ?? "Player #\(pid)",
                    position: player?.displayPosition ?? "?",
                    value: value
                )
            }
            .sorted(by: { $0.value > $1.value })

        ScrollView {
            VStack(spacing: XomperTheme.Spacing.xs) {
                ForEach(players) { entry in
                    Button {
                        switch context.side {
                        case .a: tradeSideAPlayerIds.append(entry.playerId)
                        case .b: tradeSideBPlayerIds.append(entry.playerId)
                        }
                        showSidePicker = nil
                    } label: {
                        tradePickerRow(name: entry.name, badge: entry.position, value: entry.value)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .padding(XomperTheme.Spacing.md)
        }
        .background(XomperColors.bgDark)
        .navigationTitle("Add player from \(context.teamName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showSidePicker = nil }
                    .foregroundStyle(XomperColors.championGold)
            }
        }
    }

    @ViewBuilder
    private func tradePickSelectionList(context: TradeSidePickerContext) -> some View {
        let alreadyPicked: Set<String> = {
            switch context.side {
            case .a: return Set(tradeSideAPickNames)
            case .b: return Set(tradeSideBPickNames)
            }
        }()
        // Default to current + next 2 NFL years from the device clock —
        // the trade analyzer cares about the immediately tradeable picks.
        let currentYear = Calendar.current.component(.year, from: Date())
        let years: Set<Int> = [currentYear, currentYear + 1, currentYear + 2]
        let names = valuesStore.pickNames(forYears: years)
            .filter { !alreadyPicked.contains($0) }

        ScrollView {
            if names.isEmpty {
                EmptyStateView(
                    icon: "ticket",
                    title: "No Pick Values",
                    message: "FantasyCalc didn't return tradeable pick values for the current + next two seasons. Pull to refresh values to retry."
                )
                .padding(.top, XomperTheme.Spacing.xl)
            } else {
                VStack(spacing: XomperTheme.Spacing.xs) {
                    Text("Pick values are league-wide — add a pick that you actually own. Trades aren't validated against Sleeper roster ownership in v2.")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .padding(.horizontal, XomperTheme.Spacing.sm)

                    ForEach(names, id: \.self) { name in
                        Button {
                            switch context.side {
                            case .a: tradeSideAPickNames.append(name)
                            case .b: tradeSideBPickNames.append(name)
                            }
                            showSidePicker = nil
                        } label: {
                            tradePickerRow(
                                name: name,
                                badge: "PICK",
                                value: valuesStore.pickValue(for: name)
                            )
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
                .padding(XomperTheme.Spacing.md)
            }
        }
        .background(XomperColors.bgDark)
        .navigationTitle("Add pick to \(context.teamName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showSidePicker = nil }
                    .foregroundStyle(XomperColors.championGold)
            }
        }
    }

    private func tradePickerRow(name: String, badge: String, value: Int) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
            Text(badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    // MARK: - Recommended trades

    private func recommendedTradesSection(
        myAnalysis: TeamAnalysis,
        analyses: [TeamAnalysis]
    ) -> some View {
        let recs = RecommendedTradeBuilder.recommend(
            myAnalysis: myAnalysis,
            analyses: analyses,
            rosters: leagueStore.myLeagueRosters,
            playerStore: playerStore,
            valuesStore: valuesStore
        )

        return VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Recommended trades")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(XomperColors.textMuted)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.top, XomperTheme.Spacing.md)

            if recs.isEmpty {
                Text("No fair-value upgrades found right now. Either you don't have a position below 85% of league avg, or no partner's surplus matches your strength positions within 5%.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .padding(.horizontal, XomperTheme.Spacing.md)
            } else {
                ForEach(recs) { rec in
                    Button {
                        // Load the recommendation into the builder.
                        tradePartnerRosterId = rec.partnerRosterId
                        tradeSideAPlayerIds = [rec.give.playerId]
                        tradeSideBPlayerIds = [rec.receive.playerId]
                        tradeSideAPickNames = []
                        tradeSideBPickNames = []
                    } label: {
                        recommendedTradeRow(rec)
                    }
                    .buttonStyle(.pressableCard)
                    .padding(.horizontal, XomperTheme.Spacing.md)
                }
            }
        }
    }

    private func recommendedTradeRow(_ rec: RecommendedTrade) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Text(rec.partnerTeamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%% gap", rec.percentGap * 100))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .background(XomperColors.successGreen)
                    .clipShape(Capsule())
            }

            HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Give")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                        .textCase(.uppercase)
                    Text(rec.give.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                    Text("\(rec.give.position) · \(rec.give.value)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(XomperColors.textMuted)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.championGold)
                        .textCase(.uppercase)
                    Text(rec.receive.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                    Text("\(rec.receive.position) · \(rec.receive.value)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Tap to load into the builder above.")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Trade picker context

struct TradeSidePickerContext: Identifiable, Hashable {
    enum Side: Hashable { case a, b }
    enum Kind: Hashable { case player, pick }
    let side: Side
    let kind: Kind
    let rosterId: Int
    let teamName: String
    /// Composite ID encodes both side and kind so flipping kinds
    /// re-presents the sheet with the right list.
    var id: String {
        let sidePrefix = side == .a ? "a" : "b"
        let kindPrefix = kind == .player ? "p" : "k"
        return "\(sidePrefix)-\(kindPrefix)-\(rosterId)"
    }
}

private struct TradePickerEntry: Identifiable, Hashable {
    let playerId: String
    let name: String
    let position: String
    let value: Int
    var id: String { playerId }
}

// MARK: - Tabs

private enum AnalyzerTab: CaseIterable, Sendable {
    case compare
    case league
    case trade

    var title: String {
        switch self {
        case .compare: "Compare"
        case .league:  "League"
        case .trade:   "Trade"
        }
    }
}
