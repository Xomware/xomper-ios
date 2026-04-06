import SwiftUI

struct MyProfileView: View {
    var authStore: AuthStore
    var userStore: UserStore
    var leagueStore: LeagueStore
    var router: AppRouter

    @State private var isSigningOut = false
    @State private var showSignOutConfirmation = false
    @State private var signOutPressed = false

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                profileHeader
                sleeperLinkStatus
                leagueSection
                signOutSection
            }
            .padding(XomperTheme.Spacing.md)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await handleSignOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            AvatarView(
                avatarID: userStore.myUser?.avatar,
                size: XomperTheme.AvatarSize.xl
            )

            VStack(spacing: XomperTheme.Spacing.xs) {
                if let username = resolvedUsername {
                    Text(username)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(XomperColors.textPrimary)
                }

                if let displayName = authStore.userDisplayName,
                   displayName != resolvedUsername {
                    Text(displayName)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                }

                if let email = authStore.session?.user.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, XomperTheme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profileAccessibilityLabel)
    }

    // MARK: - Sleeper Link Status

    private var sleeperLinkStatus: some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                Text("Sleeper Account")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textPrimary)

                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            Spacer()

            if authStore.isFullySetUp {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(XomperColors.successGreen)
                    .accessibilityLabel("Linked")
            }
        }
        .xomperCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleeper account \(authStore.isFullySetUp ? "linked" : "not linked")")
    }

    // MARK: - League Section

    @ViewBuilder
    private var leagueSection: some View {
        if let league = leagueStore.myLeague {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                Text("My League")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textSecondary)
                    .padding(.leading, XomperTheme.Spacing.xs)

                leagueRow(league)
            }
        }
    }

    private func leagueRow(_ league: League) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            router.switchTab(.league)
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(
                    avatarID: league.avatar,
                    size: XomperTheme.AvatarSize.md,
                    isTeam: true
                )

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(league.displayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.sm) {
                        Label("\(league.season)", systemImage: "calendar")
                        Label("\(league.totalRosters) teams", systemImage: "person.3")
                    }
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .xomperCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(league.displayName)")
        .accessibilityHint("Double tap to open league dashboard")
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showSignOutConfirmation = true
        } label: {
            HStack {
                Spacer()

                if isSigningOut {
                    ProgressView()
                        .tint(XomperColors.errorRed)
                } else {
                    Text("Sign Out")
                        .font(.headline)
                        .foregroundStyle(XomperColors.errorRed)
                }

                Spacer()
            }
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.errorRed.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        }
        .buttonStyle(.plain)
        .scaleEffect(signOutPressed ? 0.97 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: signOutPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in signOutPressed = true }
                .onEnded { _ in signOutPressed = false }
        )
        .disabled(isSigningOut)
        .padding(.top, XomperTheme.Spacing.md)
        .accessibilityLabel("Sign out")
        .accessibilityHint("Double tap to sign out of your account")
    }

    // MARK: - Helpers

    private var resolvedUsername: String? {
        authStore.sleeperUsername ?? userStore.myUser?.username
    }

    private var statusIcon: String {
        authStore.isFullySetUp ? "link.circle.fill" : "link.circle"
    }

    private var statusColor: Color {
        authStore.isFullySetUp ? XomperColors.successGreen : XomperColors.textMuted
    }

    private var statusMessage: String {
        if authStore.isFullySetUp {
            return "Linked as \(authStore.sleeperUsername ?? "unknown")"
        }
        return "Not linked to a Sleeper account"
    }

    private var profileAccessibilityLabel: String {
        let name = resolvedUsername ?? "User"
        return "Profile for \(name)"
    }

    private func handleSignOut() async {
        isSigningOut = true
        await authStore.signOut()
        userStore.reset()
        leagueStore.reset()
        isSigningOut = false
    }
}

#Preview {
    NavigationStack {
        MyProfileView(
            authStore: AuthStore(),
            userStore: UserStore(),
            leagueStore: LeagueStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
