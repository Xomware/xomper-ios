import Foundation
import Supabase

@MainActor
@Observable
final class AuthStore {

    // MARK: - Published State

    var session: Session?
    var profile: XomperProfile?
    var isAuthenticated = false
    var isLoading = true
    var isWhitelisted = false
    var sleeperUserId: String?
    var errorMessage: String?

    // MARK: - Computed

    var needsSleeperLink: Bool {
        isAuthenticated && isWhitelisted && (sleeperUserId == nil || sleeperUserId?.isEmpty == true)
    }

    var isFullySetUp: Bool {
        isAuthenticated && isWhitelisted && sleeperUserId != nil && !(sleeperUserId?.isEmpty ?? true)
    }

    // MARK: - Init

    init() {
        Task { await listenForAuthChanges() }
    }

    // MARK: - Auth State Listener

    private func listenForAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            self.session = session
            self.isAuthenticated = session != nil

            if session != nil {
                await loadUserData()
            } else {
                clearUserData()
            }

            if event == .initialSession {
                self.isLoading = false
            }
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
        await loadProfile()
        await checkWhitelist()
        await autoLinkSleeperIfNeeded()
    }

    private func loadProfile() async {
        guard let userId = session?.user.id.uuidString else { return }

        do {
            let fetchedProfile: XomperProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            self.profile = fetchedProfile
            self.sleeperUserId = fetchedProfile.sleeperUserId
        } catch {
            // Profile may not exist yet for new users -- not a fatal error
            self.profile = nil
            self.sleeperUserId = nil
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

    /// Auto-link Sleeper account from whitelist sleeper_username if profile doesn't have one yet
    private func autoLinkSleeperIfNeeded() async {
        // Already linked
        guard sleeperUserId == nil || sleeperUserId?.isEmpty == true else { return }
        // Need a whitelist record with a sleeper username
        guard let sleeperUsername = whitelistedUser?.sleeperUsername,
              !sleeperUsername.isEmpty else { return }

        // Look up the Sleeper user by username
        let url = URL(string: "https://api.sleeper.app/v1/user/\(sleeperUsername)")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let sleeperUser = try JSONDecoder().decode(SleeperUser.self, from: data)
            let success = await linkSleeperAccount(sleeperUser: sleeperUser)
            if success {
                // Skip the manual linking step
                _ = success
            }
        } catch {
            // Auto-link failed silently — user can still link manually
        }
    }

    // MARK: - Sleeper Account Linking

    func linkSleeperAccount(sleeperUser: SleeperUser) async -> Bool {
        guard let userId = session?.user.id.uuidString else { return false }

        do {
            try await supabase
                .from("profiles")
                .upsert([
                    "id": userId,
                    "email": session?.user.email ?? "",
                    "sleeper_user_id": sleeperUser.userId,
                    "sleeper_username": sleeperUser.username ?? "",
                    "sleeper_avatar": sleeperUser.avatar ?? "",
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ])
                .execute()

            self.sleeperUserId = sleeperUser.userId
            self.profile = XomperProfile(
                id: userId,
                email: session?.user.email,
                sleeperUserId: sleeperUser.userId,
                sleeperUsername: sleeperUser.username,
                sleeperAvatar: sleeperUser.avatar,
                displayName: profile?.displayName,
                createdAt: profile?.createdAt,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            return true
        } catch {
            errorMessage = "Failed to link Sleeper account."
            return false
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
        profile = nil
        isWhitelisted = false
        sleeperUserId = nil
        errorMessage = nil
    }
}
