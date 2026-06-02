import SwiftUI

/// Live draft view — the commissioner-set order pulled from Sleeper
/// (`historyStore.upcomingDraft`). Answers "who's picking when in
/// this year's draft?" with the start time + 1-day-per-pick pace
/// estimate.
///
/// Extracted verbatim from the pre-F3 `DraftOrderView.liveContent`
/// path. Renders the round-1 slot order with the YOU badge on the
/// signed-in user's slot. Sub-tab bar lives one level up in
/// `DraftHistoryView` — this view is one of three current-season
/// children (Live / Mocks / Recap).
struct LiveDraftView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var userStore: UserStore
    var nflStateStore: NflStateStore

    /// Drives the live countdown in the header. SwiftUI's
    /// `TimelineView(.periodic:)` re-evaluates every interval so we
    /// don't need a manual Timer.
    var body: some View {
        Group {
            if historyStore.isLoadingUpcoming && historyStore.upcomingDraft == nil {
                LoadingView(message: "Loading \(nextDraftSeason) draft…")
            } else if let error = historyStore.upcomingError, historyStore.upcomingDraft == nil {
                ErrorView(message: error.localizedDescription) {
                    Task { await ensureLiveLoaded() }
                }
            } else if let draft = historyStore.upcomingDraft {
                liveDraftBody(draft: draft)
            } else {
                EmptyStateView(
                    icon: "calendar.badge.exclamationmark",
                    title: "\(nextDraftSeason) Draft Not Scheduled",
                    message: "The commissioner hasn't created next season's draft yet. Pull to refresh once it's set up."
                )
            }
        }
        .task(id: leagueStore.myLeague?.leagueId) {
            await ensureLiveLoaded()
        }
        .refreshable {
            await ensureLiveLoaded()
        }
    }

    // MARK: - Body

    private func liveDraftBody(draft: Draft) -> some View {
        let teamsBySlot = liveTeamsBySlot(draft: draft)
        let slots = liveSlots(draft: draft, teamsBySlot: teamsBySlot)
        let rounds = max(draft.settings?.rounds ?? 5, 1)
        let totalPicks = slots.count * rounds
        let firstPick = liveStartDate(draft: draft)
        let myUserId = userStore.myUser?.userId

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                liveHeaderCard(draft: draft, totalPicks: totalPicks, firstPick: firstPick)

                ForEach(1...rounds, id: \.self) { round in
                    sectionHeader("Round \(round)")
                    ForEach(slots, id: \.self) { slot in
                        let pickNo = (round - 1) * slots.count + slot
                        let team = teamsBySlot[slot]
                        let isMine = team?.userId != nil && team?.userId == myUserId
                        liveRow(
                            round: round,
                            slot: slot,
                            pickNo: pickNo,
                            team: team,
                            isMine: isMine,
                            pickDate: pickDate(firstPick: firstPick, pickNo: pickNo)
                        )
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    private func liveHeaderCard(draft: Draft, totalPicks: Int, firstPick: Date?) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                Text("\(draft.season) rookie draft")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }

            if let firstPick {
                Text("Starts \(formatted(firstPick))")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
                // Live countdown — re-evaluates every second via
                // TimelineView so we don't manage our own Timer.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownLine(target: firstPick, now: context.date)
                }
            } else {
                Text("Slot order is locked. No start time set in Sleeper yet.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            if let firstPick, totalPicks > 0,
               let end = Calendar.current.date(byAdding: .day, value: totalPicks - 1, to: firstPick) {
                Text("Pace: ~1 day per pick → final pick around \(formattedShort(end))")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    /// "Starts in 34d 5h 12m 09s" / "Drafting now" once `target` passes.
    @ViewBuilder
    private func countdownLine(target: Date, now: Date) -> some View {
        let remaining = target.timeIntervalSince(now)
        if remaining <= 0 {
            Text("Draft is live")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
        } else {
            Text(formatRemaining(remaining))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if days > 0 {
            return String(format: "%dd %02dh %02dm %02ds until first pick", days, hours, minutes, secs)
        } else if hours > 0 {
            return String(format: "%dh %02dm %02ds until first pick", hours, minutes, secs)
        } else {
            return String(format: "%dm %02ds until first pick", minutes, secs)
        }
    }

    private func liveRow(round: Int, slot: Int, pickNo: Int, team: UpcomingDraftTeam?, isMine: Bool, pickDate: Date?) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Text(String(format: "%d.%02d", round, slot))
                .font(.title3.weight(.bold))
                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textSecondary)
                .frame(width: 52, alignment: .leading)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(team?.teamName ?? "Slot \(slot)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                if let pickDate {
                    Text("Pick #\(pickNo) · ~\(formattedShort(pickDate))")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                } else {
                    Text("Pick #\(pickNo)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                }
            }

            Spacer()

            if isMine {
                Text("YOU")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(
                    isMine ? XomperColors.championGold.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(XomperColors.textMuted)
            .padding(.top, XomperTheme.Spacing.sm)
    }

    // MARK: - Helpers

    private func liveTeamsBySlot(draft: Draft) -> [Int: UpcomingDraftTeam] {
        var byUser: [String: UpcomingDraftTeam] = [:]
        for user in historyStore.upcomingUsers {
            guard let userId = user.userId else { continue }
            byUser[userId] = UpcomingDraftTeam(
                userId: userId,
                teamName: user.teamName ?? user.resolvedDisplayName,
                avatarId: user.avatar
            )
        }
        var bySlot: [Int: UpcomingDraftTeam] = [:]
        if let order = draft.draftOrder {
            for (userId, slot) in order {
                if let team = byUser[userId] {
                    bySlot[slot] = team
                }
            }
        }
        return bySlot
    }

    private func liveSlots(draft: Draft, teamsBySlot: [Int: UpcomingDraftTeam]) -> [Int] {
        let count = draft.settings?.teams
            ?? max(teamsBySlot.keys.max() ?? 0, historyStore.upcomingRosters.count)
        return Array(1...max(count, 1))
    }

    private func liveStartDate(draft: Draft) -> Date? {
        guard let epochMillis = draft.startTime, epochMillis > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1000.0)
    }

    /// Each pick gets one calendar day. Pick #N is on `start + (N - 1)
    /// days`. Picks past slot count belong to round 2+ and aren't shown
    /// in this list, so we only use this for round-1 slot rows.
    private func pickDate(firstPick: Date?, pickNo: Int) -> Date? {
        guard let firstPick else { return nil }
        return Calendar.current.date(byAdding: .day, value: pickNo - 1, to: firstPick)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d 'at' h:mm a zzz"
        return f.string(from: date)
    }

    private func formattedShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private var nextDraftSeason: String {
        nflStateStore.currentSeason.isEmpty
            ? (leagueStore.myLeague?.season ?? "next")
            : nflStateStore.currentSeason
    }

    // MARK: - Data loading

    private func ensureLiveLoaded() async {
        guard let userId = userStore.myUser?.userId else { return }
        let homeName = leagueStore.resolvedHomeLeagueName
        let season = nextDraftSeason
        await historyStore.loadUpcomingDraft(
            season: season,
            homeLeagueName: homeName,
            userId: userId
        )
    }
}
