import Foundation

/// Configurable payout / side-pot structure for a league. Drives the
/// PayoutsView projection. Hardcoded defaults live in
/// `LeaguePayouts.charlotteDynastyDefault`; future iteration moves
/// this into Supabase (`league_payouts` table).
struct LeaguePayouts: Sendable {
    let categories: [LeaguePayoutCategory]

    /// Sum of all season-long category amounts (for "if I win every
    /// pot, I make $X" comparisons).
    var totalUpside: Double {
        categories.map(\.maxAmount).reduce(0, +)
    }

    static let charlotteDynastyDefault = LeaguePayouts(categories: [
        LeaguePayoutCategory(
            id: "champion",
            label: "Champion",
            kind: .champion,
            amount: 750
        ),
        LeaguePayoutCategory(
            id: "runner_up",
            label: "Runner-Up",
            kind: .runnerUp,
            amount: 250
        ),
        LeaguePayoutCategory(
            id: "third_place",
            label: "3rd Place",
            kind: .thirdPlace,
            amount: 100
        ),
        LeaguePayoutCategory(
            id: "season_high_pf",
            label: "Highest Season Points",
            kind: .seasonHighPF,
            amount: 100
        ),
        LeaguePayoutCategory(
            id: "weekly_high",
            label: "Weekly High Scorer",
            kind: .weeklyHighScore,
            amount: 25  // per week won
        ),
        // Position MVPs — scaffolded but not yet computed. Need per-
        // player weekly points from /league/{id}/matchups/{week}; will
        // light up when PlayerPointsStore + aggregation lands.
        LeaguePayoutCategory(
            id: "qb_mvp",
            label: "QB MVP",
            kind: .positionMVP("QB"),
            amount: 50
        ),
        LeaguePayoutCategory(
            id: "rb_mvp",
            label: "RB MVP",
            kind: .positionMVP("RB"),
            amount: 50
        ),
        LeaguePayoutCategory(
            id: "wr_mvp",
            label: "WR MVP",
            kind: .positionMVP("WR"),
            amount: 50
        ),
        LeaguePayoutCategory(
            id: "te_mvp",
            label: "TE MVP",
            kind: .positionMVP("TE"),
            amount: 50
        ),
    ])
}

struct LeaguePayoutCategory: Sendable, Identifiable, Hashable {
    let id: String
    let label: String
    let kind: Kind
    /// Dollar amount paid out for this category. For weekly-high this
    /// is the per-week payout; multiply by weeks-won to get total.
    let amount: Double

    enum Kind: Sendable, Hashable {
        case champion
        case runnerUp
        case thirdPlace
        case seasonHighPF
        /// Per-week winner; tally weeks won × amount.
        case weeklyHighScore
        /// Top-scoring player at the given position across the regular
        /// season. Needs per-week player_points aggregation; v1 leaves
        /// this as "coming soon" pending PlayerPointsStore.
        case positionMVP(String)
    }

    /// Maximum the category could ever pay out for one manager. For
    /// per-week categories assumes a 14-week regular season.
    var maxAmount: Double {
        switch kind {
        case .weeklyHighScore: amount * 14
        default: amount
        }
    }
}
