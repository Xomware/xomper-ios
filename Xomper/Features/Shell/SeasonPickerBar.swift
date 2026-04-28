import SwiftUI

/// Horizontal capsule list of seasons rendered inside `HeaderBar` on
/// season-scoped destinations. Reads `seasonStore.availableSeasons` and writes
/// `seasonStore.select(_:)` on tap.
///
/// Visual contract matches the legacy inline pickers from `MatchupsView` /
/// `DraftHistoryView`:
/// - Selected: `championGold` background, `deepNavy` text, `.semibold`.
/// - Unselected: `surfaceLight` background, `textSecondary` text, `.regular`.
/// - Capsule shape, horizontal scroll, no scroll indicators.
/// - Light haptic on tap, `XomperTheme.defaultAnimation` on selection change.
///
/// Returns `EmptyView` when `availableSeasons.count <= 1` so the parent can
/// collapse its 36pt strip.
struct SeasonPickerBar: View {

    var seasonStore: SeasonStore

    var body: some View {
        if seasonStore.availableSeasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(seasonStore.availableSeasons, id: \.self) { season in
                        capsule(season)
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.sm)
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Capsule

    private func capsule(_ season: String) -> some View {
        let isSelected = seasonStore.selectedSeason == season

        return Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                seasonStore.select(season)
            }
        } label: {
            Text(season)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? XomperColors.deepNavy : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: 32)
                .background(isSelected ? XomperColors.championGold : XomperColors.surfaceLight)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Season \(season)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    let store = SeasonStore()
    store.refreshAvailable(
        matchupSeasons: ["2025", "2024"],
        draftSeasons: ["2025", "2024", "2023"],
        chainSeasons: ["2026"],
        currentSeason: "2026"
    )
    return SeasonPickerBar(seasonStore: store)
        .frame(height: 36)
        .background(XomperColors.bgDark)
        .preferredColorScheme(.dark)
}
