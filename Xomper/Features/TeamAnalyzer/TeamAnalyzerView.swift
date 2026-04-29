import SwiftUI

/// Hexagon-chart team analyzer. Shows the user's home-league team's
/// dynasty value broken down by position group, optionally overlaid
/// with another team in the league for side-by-side comparison.
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

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.lg) {
                if let myAnalysis {
                    headerCard(my: myAnalysis, opp: comparison)
                    HexagonChartView(
                        primary: myAnalysis.hexAxes,
                        comparison: comparison?.hexAxes,
                        axisMaxes: axisMaxes
                    )
                    .padding(.horizontal, XomperTheme.Spacing.md)

                    legend(my: myAnalysis, opp: comparison)
                    breakdownGrid(my: myAnalysis, opp: comparison, maxes: axisMaxes)

                    comparisonPicker(
                        analyses: analyses,
                        excludingRosterId: myAnalysis.rosterId
                    )
                } else {
                    EmptyStateView(
                        icon: "person.crop.square",
                        title: "Team Not Found",
                        message: "Could not resolve your team in this league."
                    )
                }
            }
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
    }

    private func primaryAnalysis(in analyses: [TeamAnalysis]) -> TeamAnalysis? {
        guard let userId = authStore.sleeperUserId else { return analyses.first }
        return analyses.first { $0.userId == userId } ?? analyses.first
    }

    // MARK: - Header

    private func headerCard(my: TeamAnalysis, opp: TeamAnalysis?) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Team Analyzer")
                .font(.title2.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)

            Text(opp == nil
                ? "Your roster, valued by position group."
                : "Comparing your team vs \(opp!.teamName)."
            )
            .font(.subheadline)
            .foregroundStyle(XomperColors.textSecondary)
        }
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
            Spacer()
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Breakdown grid

    private func breakdownGrid(
        my: TeamAnalysis,
        opp: TeamAnalysis?,
        maxes: [String: Int]
    ) -> some View {
        VStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(Array(my.hexAxes.enumerated()), id: \.offset) { idx, axis in
                let oppValue = opp?.hexAxes[idx].value
                breakdownRow(
                    label: axis.label,
                    myValue: axis.value,
                    oppValue: oppValue,
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
                        .foregroundStyle(XomperColors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func breakdownRow(label: String, myValue: Int, oppValue: Int?, leagueMax: Int) -> some View {
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
                .foregroundStyle(XomperColors.textPrimary)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)

            if let oppValue {
                Text("\(oppValue)")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: - Comparison picker

    private func comparisonPicker(analyses: [TeamAnalysis], excludingRosterId: Int) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Compare against")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    comparisonChip(label: "None", isSelected: comparisonRosterId == nil) {
                        comparisonRosterId = nil
                    }
                    ForEach(analyses, id: \.rosterId) { team in
                        if team.rosterId != excludingRosterId {
                            comparisonChip(
                                label: team.teamName,
                                isSelected: comparisonRosterId == team.rosterId
                            ) {
                                comparisonRosterId = team.rosterId
                            }
                        }
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
            }
        }
    }

    private func comparisonChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? XomperColors.bgDark : XomperColors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .background(isSelected ? Color.cyan : XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
        }
        .buttonStyle(.pressableCard)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
