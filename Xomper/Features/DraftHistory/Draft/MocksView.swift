import SwiftUI

/// Placeholder for the rookie-mock-draft engine. Copy + icon mirror
/// the pre-F3 `DraftOrderView.mocksPlaceholder` verbatim. Replaced
/// with the real engine in the separate Mock Drafts epic.
struct MocksView: View {
    var body: some View {
        EmptyStateView(
            icon: "wand.and.stars",
            title: "Mock Drafts Coming Soon",
            message: "A 5-round rookie mock driven by team-need scoring + multiple draft personalities. Lands in the next update."
        )
    }
}

#Preview {
    MocksView()
        .preferredColorScheme(.dark)
}
