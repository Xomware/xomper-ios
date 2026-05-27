import SwiftUI

/// Admin → Tables → Leagues (F4).
///
/// Lists every row from `whitelisted_leagues` (via
/// `GET /admin/leagues-list`). Each row surfaces the league name,
/// season, and the active / dynasty / taxi chips. Tap →
/// `.adminTablesLeagueEdit(leagueId:)`.
struct LeaguesListView: View {
    var store: AdminTablesStore
    var router: AppRouter

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Leagues")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.leagues.isEmpty {
                    await store.loadLeagues()
                }
            }
            .refreshable {
                await store.loadLeagues()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingLeagues && store.leagues.isEmpty {
            LoadingView(message: "Loading leagues…")
        } else if let error = store.leaguesError, store.leagues.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn't load leagues",
                message: error
            )
        } else if store.leagues.isEmpty {
            EmptyStateView(
                icon: "building.2",
                title: "No leagues",
                message: "Whitelisted leagues will appear here once they're added in Supabase."
            )
        } else {
            ScrollView {
                VStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(store.leagues) { league in
                        LeagueRow(league: league) {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            router.navigate(to: .adminTablesLeagueEdit(leagueId: league.leagueId))
                        }
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        }
    }
}

// MARK: - Row

private struct LeagueRow: View {
    let league: WhitelistedLeague
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XomperTheme.Spacing.md) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 36, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(league.leagueName.isEmpty ? "(unnamed)" : league.leagueName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    Text("Season \(league.season) · ID \(league.leagueId)")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.xs) {
                        chip(
                            text: league.isActive ? "Active" : "Inactive",
                            color: league.isActive ? XomperColors.successGreen : XomperColors.errorRed
                        )
                        if league.isDynasty {
                            chip(text: "Dynasty", color: XomperColors.championGold)
                        }
                        if league.hasTaxi {
                            chip(text: "Taxi", color: XomperColors.championGold)
                        }
                    }
                }
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
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(XomperColors.championGold.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(league.leagueName), season \(league.season), \(league.isActive ? "active" : "inactive")")
        .accessibilityHint("Double tap to edit")
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, XomperTheme.Spacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
