import SwiftUI

struct LoginView: View {
    var authStore: AuthStore

    @State private var authMode: AuthMode = .options
    @State private var emailMode: EmailMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localError = ""
    @State private var isSubmitting = false
    @State private var showConfirmationAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.xxl) {
                brandingSection
                authSection
                errorSection
            }
            .padding(.horizontal, XomperTheme.Spacing.lg)
            .padding(.vertical, XomperTheme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark.ignoresSafeArea())
        .alert("Check Your Email", isPresented: $showConfirmationAlert) {
            Button("OK") {
                emailMode = .signIn
                password = ""
                confirmPassword = ""
            }
        } message: {
            Text("A confirmation link has been sent to your email. Please verify your account before signing in.")
        }
    }
}

// MARK: - Subviews

private extension LoginView {

    var brandingSection: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Image("XomperBanner")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .accessibilityLabel("Xomper")

            Text("Fantasy Football Companion")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .padding(.top, XomperTheme.Spacing.xxl)
    }

    @ViewBuilder
    var authSection: some View {
        switch authMode {
        case .options:
            optionsView
        case .email:
            emailFormView
        }
    }

    var optionsView: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            GoogleSignInButton(isLoading: isSubmitting) {
                isSubmitting = true
                Task {
                    await authStore.signInWithGoogle()
                    isSubmitting = false
                }
            }

            PrimaryButton(
                title: "Continue with Email",
                icon: "envelope.fill",
                style: .secondary
            ) {
                authMode = .email
            }
        }
    }

    var emailFormView: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Text(emailMode == .signIn ? "Sign In" : "Create Account")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textPrimary)

            InputField(
                placeholder: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never
            )

            InputField(
                placeholder: "Password",
                text: $password,
                isSecure: true,
                textContentType: emailMode == .signIn ? .password : .newPassword
            )

            if emailMode == .signUp {
                InputField(
                    placeholder: "Confirm Password",
                    text: $confirmPassword,
                    isSecure: true,
                    textContentType: .newPassword
                )
            }

            PrimaryButton(
                title: emailMode == .signIn ? "Sign In" : "Sign Up",
                icon: emailMode == .signIn ? "arrow.right" : "person.badge.plus",
                isLoading: isSubmitting
            ) {
                submitEmailAuth()
            }

            Button {
                withAnimation(XomperTheme.defaultAnimation) {
                    emailMode = emailMode == .signIn ? .signUp : .signIn
                    localError = ""
                    password = ""
                    confirmPassword = ""
                }
            } label: {
                Text(emailMode == .signIn
                     ? "Don't have an account? Sign Up"
                     : "Already have an account? Sign In")
                    .font(.footnote)
                    .foregroundStyle(XomperColors.championGold)
            }
            .frame(minHeight: XomperTheme.minTouchTarget)

            Button {
                withAnimation(XomperTheme.defaultAnimation) {
                    authMode = .options
                    localError = ""
                }
            } label: {
                Text("Back to options")
                    .font(.footnote)
                    .foregroundStyle(XomperColors.textSecondary)
            }
            .frame(minHeight: XomperTheme.minTouchTarget)
        }
    }

    @ViewBuilder
    var errorSection: some View {
        let message = localError.isEmpty ? (authStore.errorMessage ?? "") : localError
        if !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundStyle(XomperColors.errorRed)
                .multilineTextAlignment(.center)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .transition(.opacity)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

// MARK: - Actions

private extension LoginView {

    func submitEmailAuth() {
        localError = ""

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            localError = "Email and password are required."
            return
        }

        if emailMode == .signUp {
            guard password.count >= 6 else {
                localError = "Password must be at least 6 characters."
                return
            }
            guard password == confirmPassword else {
                localError = "Passwords do not match."
                return
            }
        }

        isSubmitting = true

        Task {
            if emailMode == .signIn {
                await authStore.signInWithEmail(email: trimmedEmail, password: password)
            } else {
                let success = await authStore.signUp(email: trimmedEmail, password: password)
                if success && !authStore.isAuthenticated {
                    showConfirmationAlert = true
                }
            }
            isSubmitting = false
        }
    }
}

// MARK: - Types

private extension LoginView {

    enum AuthMode {
        case options
        case email
    }

    enum EmailMode {
        case signIn
        case signUp
    }
}

// MARK: - Reusable Components

private struct PrimaryButton: View {
    let title: String
    var icon: String?
    var style: Style = .primary
    var isLoading: Bool = false
    let action: () -> Void

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
        .buttonStyle(PressableCardButtonStyle(pressedScale: 0.97))
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

private struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textContentType(textContentType)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(autocapitalization)
            }
        }
        .font(.body)
        .foregroundStyle(XomperColors.textPrimary)
        .padding(XomperTheme.Spacing.md)
        .frame(minHeight: XomperTheme.minTouchTarget)
        .background(XomperColors.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .autocorrectionDisabled()
    }
}

// MARK: - Google Sign-In Button

private struct GoogleSignInButton: View {
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    googleLogo
                        .frame(width: 20, height: 20)
                    Text("Continue with Google")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .fill(Color(hex: 0x4285F4))
            )
        }
        .buttonStyle(PressableCardButtonStyle(pressedScale: 0.97))
        .disabled(isLoading)
        .accessibilityLabel("Continue with Google")
    }

    // Google "G" logo drawn with shapes
    private var googleLogo: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
            Text("G")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x4285F4))
        }
    }
}

#Preview {
    LoginView(authStore: AuthStore())
        .preferredColorScheme(.dark)
}
