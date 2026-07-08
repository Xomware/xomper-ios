import SwiftUI

/// Top header bar above the navigation stack:
/// - Leading 44pt button: avatar → opens drawer
/// - Centered: "Xomper" wordmark
/// - Trailing 44pt button: magnifying glass → search route
///
/// On season-scoped destinations (`.matchups`, `.draftHistory`, `.worldCup`),
/// a 36pt sub-row appears below the wordmark hosting `SeasonPickerBar`.
/// The sub-row collapses when there is only one (or zero) seasons available
/// to avoid a 36pt empty strip.
///
/// Heights:
/// - Wordmark row: 44pt fixed.
/// - Sub-row:      36pt when visible, otherwise 0.
struct HeaderBar: View {
    let navStore: NavigationStore
    let router: AppRouter
    let avatarID: String?
    let seasonStore: SeasonStore
    let leagueName: String?

    /// Destinations that opt into the season picker sub-row. Other
    /// destinations render only the 44pt wordmark row.
    /// World Cup is intentionally excluded — it's a cumulative 3-year
    /// tournament, season filtering does not apply.
    private static let seasonScopedDestinations: Set<TrayDestination> = [
        .matchups,
        .draftHistory,
        .matchupHistory,
        .payouts,
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            if showsPickerRow {
                SeasonPickerBar(seasonStore: seasonStore)
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
                    .background(XomperColors.bgDark)
            }
        }
        .background(XomperColors.bgDark)
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            // Avatar (opens drawer).
            Button {
                navStore.openDrawer()
            } label: {
                AvatarView(avatarID: avatarID, size: 32)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel("Open menu")
            .accessibilityHint("Shows standings, history, roster and settings")
            .accessibilityAddTraits(.isButton)

            // Title section - shows destination or Xomper on landing
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                if showsSubtitle, let leagueName, !leagueName.isEmpty {
                    Text(leagueName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(XomperColors.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Search.
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                router.navigate(to: .search)
                navStore.closeDrawer()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(XomperColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(XomperColors.surfaceLight.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel("Search")
            .accessibilityHint("Search for users or leagues")
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .frame(height: 56)
    }

    private var headerTitle: String {
        navStore.currentDestination == .landing
            ? "Xomper"
            : navStore.currentDestination.title
    }

    private var showsSubtitle: Bool {
        navStore.currentDestination == .landing
    }

    // MARK: - Sub-row visibility

    private var showsPickerRow: Bool {
        guard Self.seasonScopedDestinations.contains(navStore.currentDestination) else {
            return false
        }
        return seasonStore.availableSeasons.count > 1
    }
}
