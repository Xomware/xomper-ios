import SwiftUI

/// Year picker pushed from `ArchiveView`'s "Past Drafts" card. Lists every
/// past season we have draft history loaded for (excluding the current NFL
/// season — that's already reachable directly from the Draft tab). Selecting
/// a row sets the shared `SeasonStore.selectedSeason` and switches the
/// top-level destination to `.draftHistory`, dropping the user on F3's
/// per-year sub-tabs for that season.
///
/// Side effect note (also called out in the F4 plan): mutating
/// `SeasonStore.selectedSeason` is global — Matchups / World Cup / etc. will
/// also reflect the new year until the user changes it back via the header
/// chip. Same caveat any other in-app season switch has.
struct PastDraftPickerView: View {
    let historyStore: HistoryStore
    let seasonStore: SeasonStore
    let navStore: NavigationStore
    let router: AppRouter

    /// Optional — used to filter the current NFL season out of the list. F3's
    /// Draft tab handles the current season as its default view, so the
    /// Archive picker stays focused on past years.
    let currentSeason: String

    var body: some View {
        Group {
            if years.isEmpty {
                EmptyStateView(
                    icon: "list.clipboard",
                    title: "No past drafts loaded",
                    message: "Open the Draft tab once to populate the archive."
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
        .navigationTitle("Past Drafts")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Rows

    private func yearRow(_ year: String) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            seasonStore.select(year)
            navStore.select(.draftHistory, router: router)
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                Image(systemName: "list.clipboard.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 32, alignment: .center)
                    .accessibilityHidden(true)

                Text("\(year) Draft")
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
        .accessibilityLabel("\(year) draft")
        .accessibilityHint("Double tap to open in Draft tab")
    }

    // MARK: - Data

    private var years: [String] {
        historyStore.availableDraftSeasons.filter { $0 != currentSeason }
    }
}

#Preview {
    NavigationStack {
        PastDraftPickerView(
            historyStore: HistoryStore(),
            seasonStore: SeasonStore(),
            navStore: NavigationStore(),
            router: AppRouter(),
            currentSeason: "2026"
        )
    }
    .preferredColorScheme(.dark)
}
