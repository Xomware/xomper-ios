import Foundation

@Observable
@MainActor
final class NflStateStore {
    private(set) var nflState: NflState?
    private(set) var isLoading = false
    private(set) var error: Error?

    private let apiClient: SleeperAPIClientProtocol

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Public

    func fetchState() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            nflState = try await apiClient.fetchNflState()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    var currentSeason: String {
        nflState?.season ?? String(Calendar.current.component(.year, from: Date()))
    }

    var currentWeek: Int {
        nflState?.displayWeek ?? 1
    }

    var isRegularSeason: Bool {
        nflState?.isRegularSeason ?? false
    }
}
