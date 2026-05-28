import SwiftUI

/// The 5 client-side mock-draft personalities. Each personality picks
/// a different "type" of GM — pure value, needs-aware, hype-chaser,
/// win-now, or pure chaos. The engine consumes one of these per pick
/// to decide who comes off the board.
///
/// This is the engine-side enum, distinct from the legacy
/// `MockDraftPersonality` (3 cases, backend wire shape) in
/// `Core/Models/MockDraftModels.swift`. The two coexist while the
/// backend wire format remains compatible.
enum DraftPersonality: String, CaseIterable, Sendable, Hashable, Identifiable {
    case bpa
    case teamFit       = "team_fit"
    case wildcard
    case winNow        = "win_now"
    case hypeTrain     = "hype_train"

    var id: String { rawValue }

    /// Whether reshuffling the seed changes this personality's output.
    /// BPA / Team Fit / Win-Now are deterministic given a fixed input,
    /// so reshuffle is a no-op. Wildcard + Hype Train use the RNG.
    var isStochastic: Bool {
        switch self {
        case .wildcard, .hypeTrain: return true
        case .bpa, .teamFit, .winNow: return false
        }
    }

    /// Stable display order — BPA first (most conventional), Wildcard
    /// last (chaos take). Team Fit / Win-Now / Hype Train sit in the
    /// middle in the order they were finalized.
    static var displayOrder: [DraftPersonality] {
        [.bpa, .teamFit, .winNow, .hypeTrain, .wildcard]
    }

    var displayName: String {
        switch self {
        case .bpa:       "Best Player Available"
        case .teamFit:   "Team Fit"
        case .wildcard:  "Wildcard"
        case .winNow:    "Win-Now"
        case .hypeTrain: "Hype Train"
        }
    }

    var blurb: String {
        switch self {
        case .bpa:
            "Picks the highest-value rookie on the board regardless of roster construction."
        case .teamFit:
            "Weights each team's positional needs against player value — closer to how real GMs draft."
        case .wildcard:
            "Random selection within the top 8 available — surfaces the chaotic alternate timelines."
        case .winNow:
            "Bumps RB and WR weights to favor immediate production over long-term upside."
        case .hypeTrain:
            "Amplifies value at the top of the board with light jitter — chases consensus."
        }
    }

    /// Accent color used by the personality card header. Matches the
    /// existing color vocabulary in `XomperColors` so the UI feels
    /// consistent with Live / Recap. Win-Now / Hype Train use ad-hoc
    /// hex values picked to read clearly against `bgCard` — they
    /// don't have semantic equivalents in `XomperColors`.
    var accentColor: Color {
        switch self {
        case .bpa:       XomperColors.championGold
        case .teamFit:   XomperColors.successGreen
        case .wildcard:  XomperColors.accentRed
        case .winNow:    Color(hex: 0x4FB3FF) // bright sky blue
        case .hypeTrain: Color(hex: 0xFFB94A) // warm amber
        }
    }

    /// SF Symbol icon shown beside the personality name in the header.
    var systemImage: String {
        switch self {
        case .bpa:       "star.fill"
        case .teamFit:   "person.3.fill"
        case .wildcard:  "die.face.5.fill"
        case .winNow:    "flame.fill"
        case .hypeTrain: "bolt.fill"
        }
    }
}
