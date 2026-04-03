import Foundation

@Observable
@MainActor
final class PlayerStore {
    private(set) var players: [String: Player] = [:]
    private(set) var isLoading = false
    private(set) var error: Error?

    private let apiClient: SleeperAPIClientProtocol
    private let cacheURL: URL
    private let etagKey = "PlayerStore.etag"

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
        self.cacheURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("players.json")
    }

    // MARK: - Public

    func loadPlayers() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        // Step 1: Load from disk cache if available
        if players.isEmpty, let cached = loadFromDisk() {
            players = cached
        }

        // Step 2: Revalidate with API using ETag
        do {
            let storedETag = UserDefaults.standard.string(forKey: etagKey)
            let result = try await apiClient.fetchAllPlayersRaw(etag: storedETag)

            switch result {
            case .notModified:
                break
            case .updated(let data, let newEtag):
                let decoded = try JSONDecoder().decode([String: Player].self, from: data)
                players = decoded
                saveToDisk(data: data, etag: newEtag)
            }
        } catch {
            // If we have cached data, the error is non-fatal
            if players.isEmpty {
                self.error = error
            }
        }

        isLoading = false
    }

    func player(for id: String) -> Player? {
        players[id]
    }

    func search(query: String, limit: Int = 25) -> [Player] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return players.values
            .filter { player in
                player.searchFullName?.contains(q) == true ||
                player.firstName?.lowercased().contains(q) == true ||
                player.lastName?.lowercased().contains(q) == true
            }
            .prefix(limit)
            .sorted { ($0.searchRank ?? Int.max) < ($1.searchRank ?? Int.max) }
    }

    // MARK: - Private

    private func loadFromDisk() -> [String: Player]? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: cacheURL)
            return try JSONDecoder().decode([String: Player].self, from: data)
        } catch {
            return nil
        }
    }

    private func saveToDisk(data: Data, etag: String?) {
        Task.detached(priority: .utility) { [cacheURL, etagKey] in
            try? data.write(to: cacheURL, options: .atomic)
            if let etag {
                UserDefaults.standard.set(etag, forKey: etagKey)
            }
        }
    }
}
