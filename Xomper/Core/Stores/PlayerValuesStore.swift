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
    /// Pick name → dynasty value. Pick names come from FantasyCalc
    /// (e.g. "2026 Mid 1st", "2027 Early 2nd"). Used by the trade
    /// analyzer's pick selector.
    private(set) var pickValuesByName: [String: Int] = [:]
    /// Pick name → year (e.g. "2026"), parsed from the leading
    /// 4-digit prefix in the pick name. Used to filter to current +
    /// near-future years in the trade picker.
    private(set) var pickYearsByName: [String: Int] = [:]
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
            var picksByName: [String: Int] = [:]
            var pickYearsByName: [String: Int] = [:]
            byId.reserveCapacity(decoded.count)
            posById.reserveCapacity(decoded.count)
            for entry in decoded {
                if entry.isPick {
                    guard let name = entry.name, !name.isEmpty else { continue }
                    picksByName[name] = entry.value
                    // Year prefix: first 4 digits in the name string.
                    if let year = parseYearPrefix(name) {
                        pickYearsByName[name] = year
                    }
                } else {
                    guard let sid = entry.sleeperId, !sid.isEmpty else { continue }
                    byId[sid] = entry.value
                    if let pos = entry.position { posById[sid] = pos }
                }
            }
            self.valuesById = byId
            self.positionsById = posById
            self.pickValuesByName = picksByName
            self.pickYearsByName = pickYearsByName
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

    /// Lookup pick value by display name (e.g. "2026 Mid 1st").
    func pickValue(for name: String) -> Int {
        pickValuesByName[name] ?? 0
    }

    /// All pick names currently fetchable, sorted by value desc so
    /// the trade picker leads with the highest-value picks.
    var allPickNames: [String] {
        pickValuesByName.keys.sorted { (pickValuesByName[$0] ?? 0) > (pickValuesByName[$1] ?? 0) }
    }

    /// Pick names filtered to a year range (e.g. current + next 2
    /// years). Sorted by value desc.
    func pickNames(forYears years: Set<Int>) -> [String] {
        pickValuesByName.keys
            .filter { years.contains(pickYearsByName[$0] ?? -1) }
            .sorted { (pickValuesByName[$0] ?? 0) > (pickValuesByName[$1] ?? 0) }
    }

    var hasValues: Bool {
        !valuesById.isEmpty
    }
}

/// Parse the leading 4-digit year prefix from a FantasyCalc pick name
/// like "2026 Mid 1st" or "2027 Early 2nd". Returns nil if the name
/// doesn't start with a 4-digit token. Top-level so it stays
/// nonisolated (the store decode path is on the main actor but the
/// parse itself is pure).
private func parseYearPrefix(_ name: String) -> Int? {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    let prefix = trimmed.prefix(4)
    guard prefix.count == 4 else { return nil }
    return Int(prefix)
}
