import Foundation

@Observable
@MainActor
final class UserStore {

    // MARK: - State

    private(set) var myUser: SleeperUser?
    private(set) var currentUser: SleeperUser?
    private(set) var isLoading = false
    private(set) var error: Error?

    private let apiClient: SleeperAPIClientProtocol

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Load My User

    func loadMyUser(userId: String) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            myUser = try await apiClient.fetchUser(userId)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Set Current User

    func setCurrentUser(_ user: SleeperUser) {
        currentUser = user
    }

    // MARK: - Reset

    func reset() {
        myUser = nil
        currentUser = nil
        error = nil
    }
}
