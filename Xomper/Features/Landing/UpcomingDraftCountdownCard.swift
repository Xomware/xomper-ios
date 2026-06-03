import SwiftUI

/// Landing-page card that surfaces an active "pre_draft" or "drafting"
/// upcoming draft. Renders the start time + a live countdown so the
/// home screen has something live during the offseason (when standings
/// + matchups are both empty). Tapping pushes the Draft tray
/// destination so the user lands on the Live sub-tab.
///
/// Hides itself entirely when there's no upcoming draft for the
/// current season. Reuses `HistoryStore.upcomingDraft` so we don't
/// duplicate the Sleeper fetch — the Live tab loads the same record.
struct UpcomingDraftCountdownCard: View {
    var historyStore: HistoryStore
    var leagueStore: LeagueStore
    var nflStateStore: NflStateStore
    var userStore: UserStore
    var navStore: NavigationStore
    var router: AppRouter

    var body: some View {
        if let draft = historyStore.upcomingDraft,
           let firstPick = startDate(draft: draft) {
            Button {
                navStore.select(.draftHistory, router: router)
            } label: {
                content(draft: draft, firstPick: firstPick)
            }
            .buttonStyle(.pressableCard)
            .task(id: leagueStore.myLeague?.leagueId) {
                await loadIfNeeded()
            }
        } else {
            Color.clear
                .frame(height: 0)
                .task(id: leagueStore.myLeague?.leagueId) {
                    await loadIfNeeded()
                }
        }
    }

    // MARK: - Content

    private func content(draft: Draft, firstPick: Date) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(XomperColors.championGold)
                Text("UPCOMING DRAFT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .tracking(0.5)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }

            Text("\(draft.season) Rookie Draft")
                .font(.title3.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)

            Text("Starts \(formatted(firstPick))")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                countdownLine(target: firstPick, now: context.date)
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

    @ViewBuilder
    private func countdownLine(target: Date, now: Date) -> some View {
        let remaining = target.timeIntervalSince(now)
        if remaining <= 0 {
            Text("Drafting now")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
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
            return String(format: "%dd %02dh %02dm %02ds", days, hours, minutes, secs)
        } else if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, secs)
        } else {
            return String(format: "%dm %02ds", minutes, secs)
        }
    }

    // MARK: - Helpers

    private func startDate(draft: Draft) -> Date? {
        guard let epochMillis = draft.startTime, epochMillis > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1000.0)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d 'at' h:mm a zzz"
        return f.string(from: date)
    }

    private func loadIfNeeded() async {
        guard let userId = userStore.myUser?.userId else { return }
        // Re-use the same loader the Live tab calls — internally
        // cached per-season so the call is cheap when both surfaces
        // hit it.
        let season = nflStateStore.currentSeason.isEmpty
            ? (leagueStore.myLeague?.season ?? "")
            : nflStateStore.currentSeason
        guard !season.isEmpty else { return }
        await historyStore.loadUpcomingDraft(
            season: season,
            homeLeagueName: leagueStore.resolvedHomeLeagueName,
            userId: userId
        )
    }
}
