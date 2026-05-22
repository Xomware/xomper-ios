import SwiftUI

/// Sub-tabs for the Draft surface (legacy `Features/DraftHistory/`
/// directory). Per the F3 Season Refocus plan, the current-season
/// view exposes [.live, .mocks, .recap]; past seasons collapse to
/// [.picks, .recap]. The view that hosts these is `DraftHistoryView`,
/// which is the orchestrator after F3.
///
/// `DraftSubTabBar` mirrors the pill-segmented styling that lived in
/// `DraftOrderView.viewModeBar` before F3 — championGold fill for
/// the selected pill, dim text otherwise.
enum DraftSubTab: String, CaseIterable, Identifiable, Sendable, Hashable {
    case live
    case mocks
    case recap
    case picks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live:  "Live"
        case .mocks: "Mocks"
        case .recap: "Recap"
        case .picks: "Picks"
        }
    }
}

/// Pill-segmented control for the Draft sub-tabs. Renders one button
/// per entry in `tabs`, championGold fill on the selected pill,
/// muted text otherwise. Layout + styling mirrors the pre-F3
/// `DraftOrderView.viewModeBar` so the visual language matches across
/// the app.
struct DraftSubTabBar: View {
    let tabs: [DraftSubTab]
    @Binding var selection: DraftSubTab

    var body: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(2)
        .background(XomperColors.surfaceLight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md + 2))
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
    }

    private func tabButton(_ tab: DraftSubTab) -> some View {
        let isSelected = selection == tab
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                selection = tab
            }
        } label: {
            Text(tab.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? XomperColors.bgDark : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isSelected ? XomperColors.championGold : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Sub-tab list helpers

/// Pure helpers for the sub-tab list. Lifted to a namespace so tests
/// can drive them without view materialization.
enum DraftSubTabSelection {

    /// Sub-tabs the Draft surface shows for a given season. Current
    /// season → Live / Mocks / Recap. Past season → Picks / Recap.
    static func availableSubTabs(isCurrentSeason: Bool) -> [DraftSubTab] {
        isCurrentSeason ? [.live, .mocks, .recap] : [.picks, .recap]
    }

    /// Default selection for a given mode. Current → `.live`, past
    /// → `.picks`. Used on first render and on season-change reset.
    static func defaultSubTab(isCurrentSeason: Bool) -> DraftSubTab {
        availableSubTabs(isCurrentSeason: isCurrentSeason).first ?? .recap
    }
}
