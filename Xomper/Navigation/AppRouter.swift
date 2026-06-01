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

    /// Pushed from `AdminView`'s menu — opens the Tables sub-screen
    /// (Users / Leagues / Reports flags menu). F4 deliverable.
    case adminTables

    /// Pushed from `AdminView`'s menu — stub destination for F5's
    /// Logs sub-feature (CloudWatch tail + search).
    case adminLogs

    /// Pushed from `AdminView`'s menu — opens the Audit feed (recent
    /// admin actions, paginated via cursor). F4 deliverable.
    case adminAudit

    /// Pushed from `AdminView`'s menu — opens the Cron Settings
    /// sub-screen (per-lambda kill switch + test-mode toggles).
    case adminCronSettings

    /// Pushed from `AdminView`'s menu — opens the Announcements
    /// admin list (all rows including inactive + expired).
    case adminAnnouncements

    /// Pushed from `AnnouncementsListView` — typed edit form for one
    /// `league_announcements` row. `id == nil` means create a new row;
    /// otherwise edit the row with that uuid.
    case adminAnnouncementEdit(id: UUID?)

    // MARK: - Admin Portal (F4)

    /// Pushed from `TablesSubScreenView` — list of all
    /// `whitelisted_users` rows with role + status chips. Tap a row
    /// to drill into `.adminTablesUserEdit`.
    case adminTablesUsers

    /// Pushed from `TablesSubScreenView` — list of all
    /// `whitelisted_leagues` rows. Tap a row to drill into
    /// `.adminTablesLeagueEdit`.
    case adminTablesLeagues

    /// Pushed from `UsersListView` — typed edit form for one
    /// `whitelisted_users` row (email + display_name + is_admin +
    /// is_active). `userId` matches `WhitelistedUser.sleeperUserId`.
    case adminTablesUserEdit(userId: String)

    /// Pushed from `LeaguesListView` — typed edit form for one
    /// `whitelisted_leagues` row (league_name + is_active + is_dynasty
    /// + has_taxi). `leagueId` matches `WhitelistedLeague.leagueId`.
    case adminTablesLeagueEdit(leagueId: String)

    /// Pushed from `AuditFeedView` — detail view for one audit row
    /// (before/after/metadata as collapsible JSON blocks). `entryId`
    /// matches `AuditEntry.id` (the Supabase UUID PK).
    case adminAuditDetail(entryId: String)

    // MARK: - Admin Portal (F2)

    /// Pushed from `AIReviewSubScreen` after a successful dry-run
    /// trigger. Hosts the pre-broadcast email preview list — one row
    /// per active whitelisted user. Source data lives in
    /// `AdminStore.lastPreviewsByType[reportType]`. F2 deliverable.
    case adminAIReviewPreview(reportType: AIReportType)
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
