import Foundation
import Supabase

@MainActor
@Observable
final class AuthStore {

    // MARK: - Published State

    var session: Session?
    var isAuthenticated = false
    var isLoading = true
    var isWhitelisted = false
    var sleeperUserId: String?
    var errorMessage: String?

    // MARK: - Computed

    var userEmail: String? { session?.user.email }
    var userDisplayName: String? { whitelistedUser?.displayName }
    var sleeperUsername: String? { whitelistedUser?.sleeperUsername }

    var isFullySetUp: Bool {
        isAuthenticated && isWhitelisted && sleeperUserId != nil
    }

    // MARK: - Dependencies

    private let pushManager: PushNotificationManager
    private let apiClient: XomperAPIClientProtocol

    // MARK: - Init

    init(
        pushManager: PushNotificationManager = PushNotificationManager.shared,
        apiClient: XomperAPIClientProtocol = XomperAPIClient()
    ) {
        self.pushManager = pushManager
        self.apiClient = apiClient
        Task { await listenForAuthChanges() }
    }

    // MARK: - Auth State Listener

    private func listenForAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            self.session = session
            self.isAuthenticated = session != nil

            if session != nil {
                // Show loading while resolving whitelist + Sleeper user
                self.isLoading = true
                await loadUserData()
            } else {
                clearUserData()
            }

            self.isLoading = false
        }
    }

    // MARK: - Google OAuth

    func signInWithGoogle() async {
        errorMessage = nil
        do {
            try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: Config.oauthCallbackURL)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Email Auth

    func signInWithEmail(email: String, password: String) async {
        errorMessage = nil
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            self.session = session
            self.isAuthenticated = true
            await loadUserData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async -> Bool {
        errorMessage = nil
        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password
            )
            if let session = response.session {
                self.session = session
                self.isAuthenticated = true
                await loadUserData()
                return true
            }
            // Email confirmation required
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        errorMessage = nil

        // Unregister device token before signing out
        if let token = pushManager.deviceToken, let userId = sleeperUserId {
            try? await apiClient.unregisterDevice(userId: userId, deviceToken: token)
        }

        do {
            try await supabase.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        session = nil
        isAuthenticated = false
        clearUserData()
    }

    // MARK: - Data Loading

    private func loadUserData() async {
        await checkWhitelist()
        await resolveSleeperUser()
        await registerForPushNotifications()
    }

    private func registerForPushNotifications() async {
        await pushManager.requestPermission()

        if let token = pushManager.deviceToken, let userId = sleeperUserId {
            try? await apiClient.registerDevice(userId: userId, deviceToken: token)
        }
    }

    /// Resolve Sleeper user ID from the whitelist's sleeper_username via Sleeper API
    private func resolveSleeperUser() async {
        guard let sleeperUsername = whitelistedUser?.sleeperUsername,
              !sleeperUsername.isEmpty else { return }

        let url = URL(string: "https://api.sleeper.app/v1/user/\(sleeperUsername)")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let sleeperUser = try JSONDecoder().decode(SleeperUser.self, from: data)
            self.sleeperUserId = sleeperUser.userId
        } catch {
            // Failed to resolve — app will work but without "my team" features
        }
    }

    private var whitelistedUser: WhitelistedUser?

    func checkWhitelist() async {
        guard let email = session?.user.email else {
            isWhitelisted = false
            return
        }

        do {
            let results: [WhitelistedUser] = try await supabase
                .from("whitelisted_users")
                .select()
                .eq("email", value: email.lowercased())
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            self.whitelistedUser = results.first
            self.isWhitelisted = !results.isEmpty
        } catch {
            self.isWhitelisted = false
        }
    }



    // MARK: - Handle OAuth Callback

    func handleOpenURL(_ url: URL) {
        Task {
            do {
                try await supabase.auth.session(from: url)
            } catch {
                errorMessage = "Failed to complete sign in."
            }
        }
    }

    // MARK: - Helpers

    private func clearUserData() {
        isWhitelisted = false
        sleeperUserId = nil
        errorMessage = nil
    }
}
