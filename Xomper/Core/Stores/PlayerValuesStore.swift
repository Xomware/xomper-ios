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

    /// The single in-flight fetch, if one is running. Concurrent callers
    /// await this instead of returning early — fixes race where News
    /// builds with an empty store while another view's fetch is running.
    private var loadTask: Task<Void, Never>?

    /// FantasyCalc query: dynasty, 2-QB (superflex), 12-team, full PPR.
    /// Closest publicly-available proxy for our league's TE-premium
    /// scoring; FantasyCalc doesn't expose a TE+ toggle in the URL but
    /// the values track close enough for relative team comparison.
    private let endpoint = URL(string: "https://api.fantasycalc.com/values/current?isDynasty=true&numQbs=2&numTeams=12&ppr=1&limit=2000")!

    /// Fetch values from FantasyCalc unless they were loaded within
    /// the last 12 hours (values move slowly in dynasty — daily refresh
    /// is plenty). `forceRefresh` bypasses the freshness check.
    ///
    /// Concurrent callers are coalesced onto a single in-flight fetch:
    /// awaiting `loadValues()` guarantees `valuesById` is populated on
    /// return. (The old `guard !isLoading` pattern broke that contract —
    /// a second caller returned immediately with an empty store while
    /// the first load was still running, so NewsBuilder baked in zeros.)
    func loadValues(forceRefresh: Bool = false) async {
        // A fetch is already running — wait for it rather than skipping.
        if let existing = loadTask {
            await existing.value
            return
        }

        // Fresh enough and already populated — nothing to do.
        if !forceRefresh,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < 12 * 60 * 60,
           !valuesById.isEmpty {
            return
        }

        let task = Task {
            await self.performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
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
            var pickYears: [String: Int] = [:]
            byId.reserveCapacity(decoded.count)
            posById.reserveCapacity(decoded.count)
            for entry in decoded {
                if entry.isPick {
                    guard let name = entry.name, !name.isEmpty else { continue }
                    picksByName[name] = entry.value
                    if let year = parseYearPrefix(name) {
                        pickYears[name] = year
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
            self.pickYearsByName = pickYears
            self.lastLoadedAt = Date()

            #if DEBUG
            print("[PlayerValuesStore] Loaded \(byId.count) players, \(picksByName.count) picks")
            #endif
        } catch {
            self.error = error
            #if DEBUG
            print("[PlayerValuesStore] Load failed: \(error)")
            #endif
        }
    }

    func value(for playerId: String) -> Int {
        valuesById[playerId] ?? 0
    }

    func position(for playerId: String) -> String? {
        positionsById[playerId]
    }

    /// Lookup pick value by display name. Accepts both FantasyCalc
    /// format ("2026 Mid 1st") and the tierless display name ("2026 1st").
    /// For tierless names, returns the matching tier value from the catalog.
    func pickValue(for name: String) -> Int {
        // Exact match first (handles FantasyCalc-format names).
        if let exact = pickValuesByName[name] { return exact }

        // Tierless format: "2026 1st" → find "2026 1st" in catalog.
        // FantasyCalc now uses this format (no Early/Mid/Late tiers).
        let parts = name.split(separator: " ")
        guard parts.count == 2, let year = Int(parts[0]) else { return 0 }
        let ordinal = String(parts[1])  // "1st", "2nd", …

        // Find any pick matching this year + ordinal.
        let matches = pickValuesByName.keys.filter { key in
            pickYearsByName[key] == year && key.hasSuffix(ordinal)
        }
        guard !matches.isEmpty else { return 0 }

        // Prefer exact match, otherwise take the first.
        if let direct = matches.first(where: { $0 == name }) {
            return pickValuesByName[direct] ?? 0
        }
        return pickValuesByName[matches.first!] ?? 0
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
