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

        // Step 1: Load from disk cache if available (empty cache is treated as no cache)
        if players.isEmpty, let cached = loadFromDisk() {
            players = cached
        }

        // Step 2: Revalidate with API using ETag
        await fetchAndApplyPlayers()

        isLoading = false
    }

    // MARK: - Private

    /// Fetches from Sleeper, applying the stored ETag for conditional requests.
    /// If the server returns 304 but our local store is empty (poisoned cache),
    /// clears the stored ETag and retries with a forced fresh fetch.
    private func fetchAndApplyPlayers() async {
        do {
            let storedETag = UserDefaults.standard.string(forKey: etagKey)
            let result = try await apiClient.fetchAllPlayersRaw(etag: storedETag)

            switch result {
            case .notModified:
                // Cache confirmed up-to-date — but if local store is empty the
                // on-disk cache was poisoned (e.g. written as `{}`). Clear the
                // ETag and force a fresh fetch so players actually populate.
                if players.isEmpty {
                    UserDefaults.standard.removeObject(forKey: etagKey)
                    await fetchAndApplyPlayers()
                }
            case .updated(let data, let newEtag):
                let decoded = try JSONDecoder().decode([String: Player].self, from: data)
                if decoded.isEmpty {
                    // Server returned a valid but empty payload — do not poison
                    // the cache. Surface an error so the UI can show a retry.
                    self.error = PlayerStoreError.emptyPayload
                } else {
                    players = decoded
                    saveToDisk(data: data, etag: newEtag)
                }
            }
        } catch {
            // If we have cached data, the network/decode error is non-fatal
            if players.isEmpty {
                self.error = error
            }
        }
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

    // MARK: - Cache helpers

    private func loadFromDisk() -> [String: Player]? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoded = try JSONDecoder().decode([String: Player].self, from: data)
            // An empty dict means the cache was poisoned — treat as no cache
            return decoded.isEmpty ? nil : decoded
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

// MARK: - Errors

enum PlayerStoreError: LocalizedError {
    case emptyPayload

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "Player data returned from Sleeper was empty. Please try again."
        }
    }
}
