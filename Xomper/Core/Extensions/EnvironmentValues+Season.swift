import SwiftUI

/// Environment key carrying the shared `SeasonStore` down to season-scoped
/// destinations. Optional so previews/tests can skip injection (consumers read
/// `seasonStore?.selectedSeason ?? ""`).
private struct SelectedSeasonKey: EnvironmentKey {
    static let defaultValue: SeasonStore? = nil
}

extension EnvironmentValues {
    /// Shared `SeasonStore` propagated from `MainShell`. Read by season-scoped
    /// views (`MatchupsView`, `DraftHistoryView`, `WorldCupView`) so the
    /// header-bar season picker drives them in lockstep.
    var selectedSeason: SeasonStore? {
        get { self[SelectedSeasonKey.self] }
        set { self[SelectedSeasonKey.self] = newValue }
    }
}
