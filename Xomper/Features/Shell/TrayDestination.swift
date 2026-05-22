import Foundation

/// Top-level navigation targets reachable from the slide-out drawer.
/// `currentDestination` on `NavigationStore` is always one of these.
///
/// Cases are grouped logically by the drawer sections:
/// - Home:     landing
/// - Compete:  standings, matchups, playoffs
/// - History:  draftHistory, matchupHistory, worldCup
/// - Roster:   myTeam, taxiSquad
/// - Rules:    rulebook, scoring, leagueSettings, ruleProposals
/// - Archive:  archive (hubs past standings + past matchups + past drafts)
/// - Profile/Settings are surfaced via the profile card and pinned footer.
enum TrayDestination: Hashable {
    case landing
    case standings
    case matchups
    case playoffs
    // Legacy name — the user-facing label is "Draft" and the
    // renderer is the post-F3 sub-tabbed `DraftHistoryView` (Live /
    // Mocks / Recap on the current season; Picks / Recap on past
    // seasons). The case + the `Features/DraftHistory/` directory
    // are kept stable to avoid cross-file churn across migrations.
    case draftHistory
    case matchupHistory
    case worldCup
    case myTeam
    case taxiSquad
    case teamAnalyzer
    case rulebook
    case scoring
    case leagueSettings
    case ruleProposals
    case payouts
    case draftOrder
    case aiReview
    case archive
    case admin
    case profile
    case settings

    /// Human-readable title — shown in the drawer row and as the navigation
    /// title when the destination is rendered.
    var title: String {
        switch self {
        case .landing:        "Home"
        case .standings:      "Standings"
        case .matchups:       "Matchups"
        case .playoffs:       "Playoffs"
        case .draftHistory:   "Draft"
        case .matchupHistory: "Matchup History"
        case .worldCup:       "World Cup"
        case .myTeam:         "My Team"
        case .taxiSquad:      "Taxi Squad"
        case .teamAnalyzer:   "Team Analyzer"
        case .rulebook:       "Rulebook"
        case .scoring:        "Scoring"
        case .leagueSettings: "League Settings"
        case .ruleProposals:  "Rule Proposals"
        case .payouts:        "Payouts"
        case .draftOrder:     "Draft Order Proposal"
        case .aiReview:       "AI Review"
        case .archive:        "Archive"
        case .admin:          "Admin"
        case .profile:        "Profile"
        case .settings:       "Settings"
        }
    }

    /// SF Symbol used both for the drawer row icon and any external pickers.
    var systemImage: String {
        switch self {
        case .landing:        "house.fill"
        case .standings:      "list.number"
        case .matchups:       "sportscourt.fill"
        case .playoffs:       "trophy.fill"
        case .draftHistory:   "list.clipboard.fill"
        case .matchupHistory: "clock.arrow.circlepath"
        case .worldCup:       "globe.americas.fill"
        case .myTeam:         "person.crop.square.fill"
        case .taxiSquad:      "bus.fill"
        case .teamAnalyzer:   "chart.dots.scatter"
        case .rulebook:       "book.fill"
        case .scoring:        "function"
        case .leagueSettings: "slider.horizontal.3"
        case .ruleProposals:  "checkmark.bubble.fill"
        case .payouts:        "dollarsign.circle.fill"
        case .draftOrder:     "list.bullet.rectangle"
        case .aiReview:       "sparkles"
        case .archive:        "archivebox.fill"
        case .admin:          "wrench.and.screwdriver.fill"
        case .profile:        "person.crop.circle.fill"
        case .settings:       "gearshape.fill"
        }
    }
}
