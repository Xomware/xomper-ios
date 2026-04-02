import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(XomperTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EmptyStateView(
        icon: "sportscourt",
        title: "No Matchups Found",
        message: "Check back when the season starts."
    )
    .preferredColorScheme(.dark)
}
