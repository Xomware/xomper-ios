import SwiftUI

struct LinkSleeperView: View {
    var authStore: AuthStore

    @State private var sleeperUsername = ""
    @State private var foundUser: SleeperUser?
    @State private var isSearching = false
    @State private var isLinking = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.xxl) {
                headerSection

                if let foundUser {
                    confirmationSection(user: foundUser)
                } else {
                    searchSection
                }

                if !errorMessage.isEmpty {
                    errorLabel
                }

                Spacer(minLength: XomperTheme.Spacing.xxl)

                signOutButton
            }
            .padding(.horizontal, XomperTheme.Spacing.lg)
            .padding(.vertical, XomperTheme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark.ignoresSafeArea())
    }
}

// MARK: - Subviews

private extension LinkSleeperView {

    var headerSection: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.championGold)
                .accessibilityHidden(true)

            Text("Link Your Sleeper Account")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textPrimary)

            Text("Enter your Sleeper username to connect your fantasy football data.")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    var searchSection: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                TextField("Sleeper username", text: $sleeperUsername)
                    .font(.body)
                    .foregroundStyle(XomperColors.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .onSubmit { searchUser() }

                if isSearching {
                    ProgressView()
                        .tint(XomperColors.championGold)
                }
            }
            .padding(XomperTheme.Spacing.md)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))

            ActionButton(
                title: "Search",
                icon: "magnifyingglass",
                isLoading: isSearching,
                isDisabled: sleeperUsername.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                searchUser()
            }
        }
    }

    func confirmationSection(user: SleeperUser) -> some View {
        VStack(spacing: XomperTheme.Spacing.lg) {
            AvatarView(avatarID: user.avatar, size: XomperTheme.AvatarSize.xl)

            VStack(spacing: XomperTheme.Spacing.xs) {
                Text(user.resolvedDisplayName)
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)

                if let username = user.username {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                }
            }

            Text("Is this your Sleeper account?")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)

            HStack(spacing: XomperTheme.Spacing.md) {
                ActionButton(
                    title: "Cancel",
                    style: .secondary
                ) {
                    withAnimation(XomperTheme.defaultAnimation) {
                        foundUser = nil
                        sleeperUsername = ""
                        errorMessage = ""
                    }
                }

                ActionButton(
                    title: "Confirm",
                    icon: "checkmark",
                    isLoading: isLinking
                ) {
                    confirmLink(user: user)
                }
            }
        }
        .xomperCard()
    }

    var errorLabel: some View {
        Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(XomperColors.errorRed)
            .multilineTextAlignment(.center)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .transition(.opacity)
            .accessibilityLabel("Error: \(errorMessage)")
    }

    var signOutButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            Task { await authStore.signOut() }
        } label: {
            Text("Sign Out")
                .font(.footnote)
                .foregroundStyle(XomperColors.textMuted)
        }
        .frame(minHeight: XomperTheme.minTouchTarget)
        .accessibilityLabel("Sign out")
    }
}

// MARK: - Actions

private extension LinkSleeperView {

    func searchUser() {
        let trimmed = sleeperUsername.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a username."
            return
        }

        errorMessage = ""
        isSearching = true

        Task {
            do {
                let apiClient = SleeperAPIClient()
                let user = try await apiClient.fetchUser(trimmed)
                withAnimation(XomperTheme.defaultAnimation) {
                    foundUser = user
                }
            } catch let error as SleeperAPIError {
                switch error {
                case .httpError(let code) where code == 404:
                    errorMessage = "User not found. Check the username and try again."
                default:
                    errorMessage = "Search failed. Please try again."
                }
            } catch {
                errorMessage = "Search failed. Please try again."
            }
            isSearching = false
        }
    }

    func confirmLink(user: SleeperUser) {
        isLinking = true
        errorMessage = ""

        Task {
            let success = await authStore.linkSleeperAccount(sleeperUser: user)
            if !success {
                errorMessage = authStore.errorMessage ?? "Failed to link account."
            }
            isLinking = false
        }
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let title: String
    var icon: String?
    var style: Style = .primary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    enum Style {
        case primary, secondary
    }

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(style == .primary ? XomperColors.deepNavy : XomperColors.textPrimary)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
            }
            .font(.headline)
            .foregroundStyle(style == .primary ? XomperColors.deepNavy : XomperColors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .background(style == .primary ? XomperColors.championGold : XomperColors.surfaceLight)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .disabled(isLoading || isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    LinkSleeperView(authStore: AuthStore())
        .preferredColorScheme(.dark)
}
