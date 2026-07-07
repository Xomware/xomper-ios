import SwiftUI

/// Filter bar for the News feed — type, team, and date-window dropdowns.
/// Mutates the shared `NewsStore` filter state directly (it's a class,
/// so writes to its `var` filters are observed by the feed).
///
/// Rendered as `Menu` dropdowns (matching `TeamAnalyzerView`'s opponent
/// picker) rather than a wall of pill toggles. Lives in a fixed strip
/// above the feed's `ScrollView`, so it stays pinned with no scroll gap.
struct NewsFilterBar: View {
    let store: NewsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                typeMenu
                if !store.availableTeams.isEmpty { teamMenu }
                dateMenu
                if store.activeFilterCount > 0 { clearButton }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Menus

    private var typeMenu: some View {
        Menu {
            Button { select { store.typeFilter = nil } } label: {
                menuRow("All Types", selected: store.typeFilter == nil)
            }
            ForEach(NewsType.allCases) { type in
                Button { select { store.typeFilter = type } } label: {
                    menuRow(type.label, selected: store.typeFilter == type)
                }
            }
        } label: {
            dropdown(store.typeFilter?.label ?? "All Types", active: store.typeFilter != nil)
        }
        .accessibilityLabel("Filter by type")
    }

    private var teamMenu: some View {
        let selectedName = store.availableTeams.first { $0.rosterId == store.teamFilter }?.name
        return Menu {
            Button { select { store.teamFilter = nil } } label: {
                menuRow("All Teams", selected: store.teamFilter == nil)
            }
            ForEach(store.availableTeams, id: \.rosterId) { team in
                Button { select { store.teamFilter = team.rosterId } } label: {
                    menuRow(team.name, selected: store.teamFilter == team.rosterId)
                }
            }
        } label: {
            dropdown(selectedName ?? "All Teams", active: store.teamFilter != nil)
        }
        .accessibilityLabel("Filter by team")
    }

    private var dateMenu: some View {
        Menu {
            ForEach(NewsDateWindow.allCases) { window in
                Button { select { store.dateFilter = window } } label: {
                    menuRow(window.label, selected: store.dateFilter == window)
                }
            }
        } label: {
            dropdown(store.dateFilter == .all ? "All Time" : store.dateFilter.label,
                     active: store.dateFilter != .all)
        }
        .accessibilityLabel("Filter by date")
    }

    private var clearButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) { store.clearFilters() }
        } label: {
            HStack(spacing: XomperTheme.Spacing.xxs) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                Text("Clear")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(XomperColors.accentRed)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .frame(minHeight: 36)
            .background(XomperColors.surfaceLight)
            .clipShape(Capsule())
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Clear filters")
    }

    // MARK: - Building blocks

    /// Capsule dropdown label — fills `championGold` when the filter is
    /// active, matching the selected state of `SeasonPickerBar`.
    private func dropdown(_ title: String, active: Bool) -> some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? XomperColors.deepNavy : XomperColors.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(active ? XomperColors.deepNavy : XomperColors.textSecondary)
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .frame(minHeight: 36)
        .background(active ? XomperColors.championGold : XomperColors.surfaceLight)
        .clipShape(Capsule())
    }

    /// One menu entry — title plus a checkmark on the active option.
    private func menuRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    /// Apply a filter mutation with a light haptic + standard animation.
    private func select(_ mutate: () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(XomperTheme.defaultAnimation) { mutate() }
    }
}
