import SwiftUI

/// Profile card pinned to the top of the drawer. Tap pushes the profile
/// destination via the supplied action.
///
/// Visual: gold-accent gradient at low opacity over `bgCard`, with a hairline
/// stroke and the user's avatar + display name + email + chevron.
struct TrayProfileCard: View {
    let avatarID: String?
    let displayName: String?
    let email: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(
                    avatarID: avatarID,
                    size: XomperTheme.AvatarSize.md
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName ?? "Your Profile")
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    if let email, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(XomperColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(XomperColors.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    XomperColors.bgCard
                    XomperColors.goldAccentGradient
                        .opacity(0.25)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.xl, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Open profile for \(displayName ?? email ?? "you")")
    }
}
