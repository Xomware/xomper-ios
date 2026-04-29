import Foundation

/// Single source of truth for the user's currently-selected season across
/// season-scoped destinations (`MatchupsView`, `DraftHistoryView`, `WorldCupView`).
///
/// Owned by `MainShell` and injected into the destination tree via
/// `EnvironmentValues.selectedSeason`. Consumers read `selectedSeason` and call
/// `select(_:)` (typically wired through `SeasonPickerBar` in `HeaderBar`).
///
/// `availableSeasons` is the descending-sorted union of:
/// - `HistoryStore.availableMatchupSeasons`
/// - `HistoryStore.availableDraftSeasons`
/// - `LeagueStore.leagueChain.map(\.season)`
///
/// Default selection on cold open = `NflStateStore.currentSeason`. If that
/// season is not present in the union, falls back to the first element of
/// `availableSeasons`.
@Observable
@MainActor
final class SeasonStore {

    // MARK: - State

    /// The currently-selected season string (e.g. `"2025"`). Empty until
    /// `bootstrap` runs. Consumers should treat empty as "no selection yet".
    private(set) var selectedSeason: String = ""

    /// Descending-sorted union of seasons across all history sources.
    private(set) var availableSeasons: [String] = []

    // MARK: - Bootstrap

    /// Seeds `selectedSeason` from `currentSeason` if no selection has been
    /// made yet. No-op if `selectedSeason` is already populated.
    func bootstrap(currentSeason: String) {
        guard selectedSeason.isEmpty else { return }
        selectedSeason = currentSeason
    }

    // MARK: - Refresh available seasons

    /// Recompute `availableSeasons` from the latest history/chain inputs.
    /// Preserves `selectedSeason` if still in the new set; otherwise falls
    /// back to `currentSeason` if present, else the first available season.
    func refreshAvailable(
        matchupSeasons: [String],
        draftSeasons: [String],
        chainSeasons: [String],
        currentSeason: String
    ) {
        var union = Set(matchupSeasons)
        union.formUnion(draftSeasons)
        union.formUnion(chainSeasons)
        // Always surface the current NFL season as a chip even before
        // we have draft/matchup data for it — that's how 2026 (about
        // to draft, no picks yet) shows up alongside completed seasons.
        if !currentSeason.isEmpty {
            union.insert(currentSeason)
        }

        let sorted = union
            .sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }

        availableSeasons = sorted

        // Preserve selection if still valid.
        if !selectedSeason.isEmpty, sorted.contains(selectedSeason) {
            return
        }

        // Fall back to current season when present in the new set.
        if !currentSeason.isEmpty, sorted.contains(currentSeason) {
            selectedSeason = currentSeason
            return
        }

        // Otherwise pick the newest available season.
        if let first = sorted.first {
            selectedSeason = first
        }
    }

    // MARK: - Selection

    /// Sets `selectedSeason` if `season` is in `availableSeasons`. No-op
    /// otherwise (defensive against stale taps after a refresh dropped the
    /// season).
    func select(_ season: String) {
        guard availableSeasons.contains(season) else { return }
        selectedSeason = season
    }
}
