import Foundation

/// Fetches + caches dynasty superflex player values from FantasyCalc.
/// Single fetch per app session; ~458 players returned, ~50KB payload.
/// No backend round-trip in v1 — direct API call.
///
/// Future: move behind the Xomper API gateway with daily-cron
/// caching so we don't hit FantasyCalc per-user. For now this is
/// fine for a 12-person league.
@Observable
@MainActor
final class PlayerValuesStore {
    /// Sleeper player ID → dynasty value. Empty until first load.
    private(set) var valuesById: [String: Int] = [:]
    private(set) var positionsById: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var lastLoadedAt: Date?

    /// FantasyCalc query: dynasty, 2-QB (superflex), 12-team, full PPR.
    /// Closest publicly-available proxy for our league's TE-premium
    /// scoring; FantasyCalc doesn't expose a TE+ toggle in the URL but
    /// the values track close enough for relative team comparison.
    private let endpoint = URL(string: "https://api.fantasycalc.com/values/current?isDynasty=true&numQbs=2&numTeams=12&ppr=1")!

    /// Fetch values from FantasyCalc unless they were loaded within
    /// the last 12 hours (values move slowly in dynasty — daily refresh
    /// is plenty). `forceRefresh` bypasses the freshness check.
    func loadValues(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        if !forceRefresh,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < 12 * 60 * 60,
           !valuesById.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode([PlayerValue].self, from: data)

            var byId: [String: Int] = [:]
            var posById: [String: String] = [:]
            byId.reserveCapacity(decoded.count)
            posById.reserveCapacity(decoded.count)
            for entry in decoded {
                guard let sid = entry.sleeperId, !sid.isEmpty else { continue }
                byId[sid] = entry.value
                if let pos = entry.position { posById[sid] = pos }
            }
            self.valuesById = byId
            self.positionsById = posById
            self.lastLoadedAt = Date()
        } catch {
            self.error = error
        }
    }

    func value(for playerId: String) -> Int {
        valuesById[playerId] ?? 0
    }

    func position(for playerId: String) -> String? {
        positionsById[playerId]
    }

    var hasValues: Bool {
        !valuesById.isEmpty
    }
}
