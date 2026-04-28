import SwiftUI

/// Top header bar above the navigation stack:
/// - Leading 44pt button: avatar → opens drawer
/// - Centered: "Xomper" wordmark
/// - Trailing 44pt button: magnifying glass → search route
///
/// Height: 44, background `XomperColors.bgDark`.
struct HeaderBar: View {
    let navStore: NavigationStore
    let router: AppRouter
    let avatarID: String?

    var body: some View {
        ZStack {
            // Center wordmark — independent of leading/trailing buttons so it
            // stays optically centered.
            Text("Xomper")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(XomperColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                // Avatar (opens drawer).
                Button {
                    navStore.openDrawer()
                } label: {
                    AvatarView(avatarID: avatarID, size: 36)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open menu")
                .accessibilityHint("Shows standings, history, roster and settings")
                .accessibilityAddTraits(.isButton)

                Spacer()

                // Search.
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    router.navigate(to: .search)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(XomperColors.championGold)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
                .accessibilityHint("Search for users or leagues")
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.sm)
        .frame(height: 44)
        .background(XomperColors.bgDark)
    }
}
