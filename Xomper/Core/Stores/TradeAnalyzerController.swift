import Foundation
import Observation

/// Shared owner of the Trade Analyzer's builder state. Hoisted out of
/// `TeamAnalyzerView` so a second consumer (My Team's Trades tab) can
/// seed a `RecommendedTrade` into the builder before the user lands
/// on the screen.
///
/// Owns five fields (the previously-private `@State` on the view):
/// - Selected partner roster
/// - Side A players + picks (the user's side — what they're giving up)
/// - Side B players + picks (the partner's side — what the user receives)
///
/// `showSidePicker` stays on the view itself — it's transient sheet
/// presentation state, not anything a deep link would seed.
///
/// Lifecycle: instantiated once at `MainShell` alongside the other
/// shared stores and injected into every consumer. The same instance
/// is shared across drawer destination switches so a preload from
/// the My Team Trades tab survives the tray flip to Team Analyzer.
@Observable
@MainActor
final class TradeAnalyzerController {

    /// Selected partner roster id. `nil` until the user picks a partner.
    var tradePartnerRosterId: Int?

    /// Player ids on the user's side (what they would give up).
    var tradeSideAPlayerIds: [String] = []

    /// Pick names on the user's side, e.g. "2026 Mid 1st".
    var tradeSideAPickNames: [String] = []

    /// Player ids on the partner's side (what the user would receive).
    var tradeSideBPlayerIds: [String] = []

    /// Pick names on the partner's side.
    var tradeSideBPickNames: [String] = []

    // MARK: - Preload

    /// Seed all five fields from a `RecommendedTrade` so the Trade
    /// Analyzer opens with the recommendation already populated.
    /// Picks are cleared — recommendations only surface single-
    /// player-for-single-player swaps today; the user can layer picks
    /// in afterward.
    func preload(_ rec: RecommendedTrade) {
        tradePartnerRosterId = rec.partnerRosterId
        tradeSideAPlayerIds  = [rec.give.playerId]
        tradeSideBPlayerIds  = [rec.receive.playerId]
        tradeSideAPickNames  = []
        tradeSideBPickNames  = []
    }

    // MARK: - Reset

    /// Clear every field. Called when the user exits the Trade tab
    /// without saving or when they explicitly start a fresh trade.
    func reset() {
        tradePartnerRosterId = nil
        tradeSideAPlayerIds  = []
        tradeSideAPickNames  = []
        tradeSideBPlayerIds  = []
        tradeSideBPickNames  = []
    }
}
