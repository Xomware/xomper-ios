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

// MARK: - Tabs

private enum AnalyzerTab: CaseIterable, Sendable {
    case compare
    case league

    var title: String {
        switch self {
        case .compare: "Compare"
        case .league:  "League"
        }
    }
}
