import SwiftUI

/// Filter bar for the News feed — type, team, and date-window chips.
/// Mutates the shared `NewsStore` filter state directly (it's a class,
/// so writes to its `var` filters are observed by the feed).
struct NewsFilterBar: View {
    let store: NewsStore

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            // Type
            chipRow {
                NewsFilterChip(title: "All", isSelected: store.typeFilter == nil) {
                    store.typeFilter = nil
                }
                ForEach(NewsType.allCases) { type in
                    NewsFilterChip(title: type.label, isSelected: store.typeFilter == type) {
                        store.typeFilter = store.typeFilter == type ? nil : type
                    }
                }
            }

            // Team — only when the feed has teams to filter by.
            if !store.availableTeams.isEmpty {
                chipRow {
                    NewsFilterChip(title: "All Teams", isSelected: store.teamFilter == nil) {
                        store.teamFilter = nil
                    }
                    ForEach(store.availableTeams, id: \.rosterId) { team in
                        NewsFilterChip(title: team.name, isSelected: store.teamFilter == team.rosterId) {
                            store.teamFilter = store.teamFilter == team.rosterId ? nil : team.rosterId
                        }
                    }
                }
            }

            // Date window
            chipRow {
                ForEach(NewsDateWindow.allCases) { window in
                    NewsFilterChip(title: window.label, isSelected: store.dateFilter == window) {
                        store.dateFilter = window
                    }
                }
            }
        }
        .padding(.vertical, XomperTheme.Spacing.sm)
    }

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                content()
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
        }
    }
}
