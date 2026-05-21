import SwiftUI

/// Compact scoreboard of the current week's matchups — Team A / VS /
/// Team B with point totals when available. Self-loading: holds its
/// own raw `[Matchup]` state and re-fetches when `leagueId`, `week`,
/// or the parent's `refreshToken` changes.
///
/// Offseason behavior: when `!nflStateStore.isRegularSeason`, renders
/// a compact empty-state card and skips the network call.
struct ThisWeekMatchupsCard: View {
    var leagueStore: LeagueStore
    var nflStateStore: NflStateStore
    var authStore: AuthStore
    var controller: ThisWeekMatchupsController

    @State private var pairs: [PairedMatchup] = []
    @State private var isLoading = false
    @State private var loadError: String?

    /// Lightweight API client instance — same pattern `HistoryStore`
    /// takes. The card owns the call; no global state.
    private let apiClient: SleeperAPIClientProtocol = SleeperAPIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            sectionHeader

            if !nflStateStore.isRegularSeason {
                offseasonEmptyState
            } else if let error = loadError, pairs.isEmpty {
                errorState(message: error)
            } else if pairs.isEmpty && isLoading {
                loadingState
            } else if pairs.isEmpty {
                noMatchupsState
            } else {
                matchupsList
            }
        }
        .task(id: taskKey) {
            await loadIfNeeded()
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Image(systemName: "sportscourt.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
            Text("WEEK \(nflStateStore.currentWeek) MATCHUPS")
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, XomperTheme.Spacing.xs)
        .accessibilityHidden(true)
    }

    // MARK: - Matchups list

    private var matchupsList: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            ForEach(pairs) { pair in
                matchupRow(pair)
            }
        }
    }

    private func matchupRow(_ pair: PairedMatchup) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            teamCell(
                teamName: pair.teamAName,
                avatarId: pair.teamAAvatar,
                points: pair.teamAPoints,
                isMine: pair.teamAIsMine,
                alignment: .leading
            )

            Text("VS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textMuted)
                .tracking(0.5)

            teamCell(
                teamName: pair.teamBName,
                avatarId: pair.teamBAvatar,
                points: pair.teamBPoints,
                isMine: pair.teamBIsMine,
                alignment: .trailing
            )
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(
                    (pair.teamAIsMine || pair.teamBIsMine)
                        ? XomperColors.championGold.opacity(0.4)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: pair))
    }

    private func teamCell(
        teamName: String,
        avatarId: String?,
        points: Double,
        isMine: Bool,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: XomperTheme.Spacing.xs) {
            AvatarView(
                avatarID: avatarId,
                size: XomperTheme.AvatarSize.sm,
                isTeam: true
            )
            Text(teamName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            Text(pointsLabel(points))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func pointsLabel(_ points: Double) -> String {
        guard points > 0 else { return "—" }
        return String(format: "%.2f", points)
    }

    private func accessibilityLabel(for pair: PairedMatchup) -> String {
        let a = "\(pair.teamAName) \(pointsLabel(pair.teamAPoints))"
        let b = "\(pair.teamBName) \(pointsLabel(pair.teamBPoints))"
        return "\(a) versus \(b)"
    }

    // MARK: - States

    private var offseasonEmptyState: some View {
        emptyCard(
            icon: "moon.zzz.fill",
            message: "This week's matchups appear here once games begin."
        )
    }

    private var loadingState: some View {
        emptyCard(
            icon: "sportscourt",
            message: "Loading this week's matchups…"
        )
    }

    private var noMatchupsState: some View {
        emptyCard(
            icon: "sportscourt",
            message: "No matchups scheduled for Week \(nflStateStore.currentWeek)."
        )
    }

    private func errorState(message: String) -> some View {
        emptyCard(
            icon: "exclamationmark.triangle.fill",
            message: "Couldn't load matchups: \(message)"
        )
    }

    private func emptyCard(icon: String, message: String) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
            Text(message)
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    // MARK: - Load

    /// Composite key for `.task(id:)` — re-fires the load whenever the
    /// home league, current week, or the controller's refresh token
    /// changes. The controller is bumped by the outer Landing
    /// pull-to-refresh.
    private var taskKey: String {
        let leagueId = leagueStore.myLeague?.leagueId ?? "none"
        return "\(leagueId)-\(nflStateStore.currentWeek)-\(controller.refreshToken.uuidString)"
    }

    private func loadIfNeeded() async {
        // Skip the network call entirely in offseason.
        guard nflStateStore.isRegularSeason else {
            pairs = []
            isLoading = false
            return
        }
        guard let leagueId = leagueStore.myLeague?.leagueId else {
            pairs = []
            isLoading = false
            return
        }

        let task = Task { @MainActor in
            await performLoad(leagueId: leagueId, week: nflStateStore.currentWeek)
        }
        controller.pendingRefresh = task
        await task.value
        controller.pendingRefresh = nil
    }

    private func performLoad(leagueId: String, week: Int) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let raw = try await apiClient.fetchLeagueMatchups(leagueId, week: week)
            pairs = Self.pair(
                raw,
                rosters: leagueStore.myLeagueRosters,
                users: leagueStore.myLeagueUsers,
                myUserId: authStore.sleeperUserId
            )
        } catch {
            loadError = error.localizedDescription
            pairs = []
        }
    }

    // MARK: - Pairing helper

    /// Groups raw matchups by `matchupId` into pairs and resolves
    /// owner names / team names / avatars from the home-league users
    /// and rosters. Replicates `HistoryStore.pairMatchupsStatic`'s
    /// grouping inline — the upstream helper is private.
    private static func pair(
        _ matchups: [Matchup],
        rosters: [Roster],
        users: [SleeperUser],
        myUserId: String?
    ) -> [PairedMatchup] {
        var grouped: [Int: [Matchup]] = [:]
        for matchup in matchups {
            guard let mid = matchup.matchupId else { continue }
            grouped[mid, default: []].append(matchup)
        }

        let rosterById = Dictionary(uniqueKeysWithValues: rosters.map { ($0.rosterId, $0) })
        let userById = Dictionary(uniqueKeysWithValues: users.compactMap { user -> (String, SleeperUser)? in
            guard let id = user.userId else { return nil }
            return (id, user)
        })

        func resolve(_ matchup: Matchup) -> (name: String, avatar: String?, isMine: Bool) {
            let roster = rosterById[matchup.rosterId]
            let ownerId = roster?.ownerId
            let user = ownerId.flatMap { userById[$0] }
            let name = user?.teamName
                ?? user?.resolvedDisplayName
                ?? "Team \(matchup.rosterId)"
            let isMine = ownerId != nil && ownerId == myUserId
            return (name, user?.avatar, isMine)
        }

        return grouped.values.compactMap { pair -> PairedMatchup? in
            guard pair.count >= 2 else { return nil }
            let a = pair[0]
            let b = pair[1]
            let infoA = resolve(a)
            let infoB = resolve(b)
            return PairedMatchup(
                matchupId: a.matchupId ?? 0,
                teamAName: infoA.name,
                teamAAvatar: infoA.avatar,
                teamAPoints: a.resolvedPoints,
                teamAIsMine: infoA.isMine,
                teamBName: infoB.name,
                teamBAvatar: infoB.avatar,
                teamBPoints: b.resolvedPoints,
                teamBIsMine: infoB.isMine
            )
        }
        .sorted { lhs, rhs in
            // My matchup first if present; then by matchupId.
            if lhs.teamAIsMine || lhs.teamBIsMine { return true }
            if rhs.teamAIsMine || rhs.teamBIsMine { return false }
            return lhs.matchupId < rhs.matchupId
        }
    }
}

/// View-local matchup model — denormalized for one-shot rendering.
/// Kept private to the file so the public API of the card is just
/// `init` + `body`.
private struct PairedMatchup: Identifiable, Sendable {
    let matchupId: Int
    let teamAName: String
    let teamAAvatar: String?
    let teamAPoints: Double
    let teamAIsMine: Bool
    let teamBName: String
    let teamBAvatar: String?
    let teamBPoints: Double
    let teamBIsMine: Bool

    var id: Int { matchupId }
}

#Preview {
    ThisWeekMatchupsCard(
        leagueStore: LeagueStore(),
        nflStateStore: NflStateStore(),
        authStore: AuthStore(),
        controller: ThisWeekMatchupsController()
    )
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
