import SwiftUI

/// Defines all navigable destinations within the app.
///
/// `leagueDashboard` is retained as a defensive case post-F3 (the legacy
/// dashboard view was dissolved into individual tray destinations). If
/// anything still pushes this route, `MainShell` falls through to standings.
enum AppRoute: Hashable {
    case leagueDashboard
    case teamDetail(rosterId: Int)
    case userProfile(userId: String)
    case draftHistory
    case matchupHistory
    case taxiSquad
    case search
    case settings
    case playerDetail(playerId: String)
    /// Browse another league at high level (standings + basic info). Used
    /// when the user taps a non-home league in profile or search. The
    /// view fetches its own data — does NOT mutate `LeagueStore.myLeague`.
    case leagueOverview(leagueId: String)
    /// Detail view for one AI-generated league report. `reportId`
    /// matches `AIReport.id` (computed from `pk|sk`) and the detail
    /// view resolves the struct from `AIReviewStore`.
    case aiReportDetail(reportId: String)

    // MARK: - Archive (F4)

    /// Pushed from `ArchiveView`'s "Past Standings" card. Lists every
    /// available historical season as a row → drills into
    /// `archiveHistoricalStandings(year:)`.
    case archivePastStandings

    /// Pushed from `archivePastStandings`. Renders that year's standings
    /// reconstructed from `MatchupHistoryRecord`s via
    /// `StandingsBuilder.buildStandingsFromHistory`.
    case archiveHistoricalStandings(year: String)

    /// Pushed from `ArchiveView`'s "Past Drafts" card. Lists past-season
    /// drafts; on selection sets `SeasonStore.selectedSeason` and switches
    /// the top-level destination to `.draftHistory`.
    case archivePastDraftPicker

    // MARK: - Admin Portal (F1)

    /// Pushed from `AdminView`'s menu — hosts the existing AI Review
    /// trigger cards + activity feed (extracted verbatim from the
    /// pre-F1 `AdminView`).
    case adminAIReview

    /// Pushed from `AdminView`'s menu — hosts the F1 test-email sender
    /// surface (recipient + report pickers, send button, receipts).
    case adminTestEmail

    /// Pushed from `AdminView`'s menu — stub destination for F4's
    /// Tables sub-feature (users / leagues / reports editing).
    case adminTables

    /// Pushed from `AdminView`'s menu — stub destination for F5's
    /// Logs sub-feature (CloudWatch tail + search).
    case adminLogs

    /// Pushed from `AdminView`'s menu — stub destination for F4's
    /// Audit sub-feature (recent admin actions feed).
    case adminAudit
}

/// Owns the inner `NavigationStack` path inside `MainShell`. The drawer
/// (via `NavigationStore`) drives top-level destination selection; this
/// router is purely about pushes / pops within the current destination's
/// stack.
@Observable
@MainActor
final class AppRouter {
    var path = NavigationPath()

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
