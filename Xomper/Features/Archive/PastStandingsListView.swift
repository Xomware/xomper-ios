import SwiftUI

/// Year list drilled into from `ArchiveView`'s "Past Standings" card. Each row
/// is a tappable card representing one historical season; selection pushes
/// `HistoricalStandingsView` for that year.
///
/// Years come from `HistoryStore.availableMatchupSeasons` — already used to
/// drive the season picker, so no extra fetch path. Descending order (newest
/// first). Empty state renders when the store has no matchup history loaded
/// at all.
struct PastStandingsListView: View {
    let historyStore: HistoryStore
    let leagueStore: LeagueStore
    let authStore: AuthStore
    let teamStore: TeamStore
    let router: AppRouter

    var body: some View {
        Group {
            if years.isEmpty {
                EmptyStateView(
                    icon: "list.number",
                    title: "No past seasons loaded",
                    message: "Open Matchup History first to load prior seasons."
                )
            } else {
                ScrollView {
                    VStack(spacing: XomperTheme.Spacing.sm) {
                        ForEach(years, id: \.self) { year in
                            yearRow(year)
                        }
                    }
                    .padding(.horizontal, XomperTheme.Spacing.md)
                    .padding(.vertical, XomperTheme.Spacing.sm)
                }
            }
        }
        .background(XomperColors.bgDark)
        .navigationTitle("Past Standings")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Rows

    private func yearRow(_ year: String) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            router.navigate(to: .archiveHistoricalStandings(year: year))
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                Image(systemName: "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 32, alignment: .center)
                    .accessibilityHidden(true)

                Text("\(year) Standings")
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(XomperColors.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(XomperTheme.Spacing.md)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .xomperShadow(.sm)
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(year) standings")
        .accessibilityHint("Double tap to view")
    }

    // MARK: - Data

    private var years: [String] {
        historyStore.availableMatchupSeasons
    }
}

#Preview {
    NavigationStack {
        PastStandingsListView(
            historyStore: HistoryStore(),
            leagueStore: LeagueStore(),
            authStore: AuthStore(),
            teamStore: TeamStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
