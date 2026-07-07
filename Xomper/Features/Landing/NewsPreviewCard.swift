import SwiftUI

/// Landing-page preview of the League News feed. Shows the three most
/// recent moves; tapping anywhere opens the full News destination.
///
/// Owns its own one-shot load (mirrors `ThisWeekMatchupsCard`) so it
/// stays self-contained on the landing surface.
struct NewsPreviewCard: View {
    var newsStore: NewsStore
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var valuesStore: PlayerValuesStore
    var navStore: NavigationStore
    var router: AppRouter

    private var previewItems: [NewsItem] {
        Array(newsStore.items.prefix(3))
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            navStore.select(.news, router: router)
        } label: {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                header

                if previewItems.isEmpty {
                    Text(newsStore.isLoading ? "Loading recent moves..." : "No recent moves yet.")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                } else {
                    ForEach(previewItems) { item in
                        previewRow(item)
                        if item.id != previewItems.last?.id {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }
                }
            }
            .padding(XomperTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(XomperColors.steelBlue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .task { await load() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("League news")
        .accessibilityHint("Double tap to see all trades and moves")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Image(systemName: "newspaper.fill")
                .font(.subheadline)
                .foregroundStyle(XomperColors.steelBlue)
            Text("LEAGUE NEWS")
                .font(.caption.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
            Text("See all")
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.steelBlue)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.steelBlue)
        }
    }

    // MARK: - Row

    private func previewRow(_ item: NewsItem) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: item.type.systemImage)
                .font(.caption)
                .foregroundStyle(item.type.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let grade = item.grade, let winnerId = grade.winnerRosterId {
                let letter = grade.letter(for: winnerId)
                Text(letter.rawValue)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(letter.color)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        guard !leagueStore.myLeagueRosters.isEmpty else { return }
        await valuesStore.loadValues()
        await newsStore.load(
            leagueId: leagueStore.resolvedHomeLeagueId,
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            valuesStore: valuesStore
        )
    }
}
