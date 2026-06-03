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

    /// View toggle — rounds list (default) vs the column-per-team
    /// draft board grid (PR #129). Reuses `DraftViewMode` so the live
    /// view feels like a sibling of past drafts.
    @State private var viewMode: DraftViewMode = .rounds

    /// True when the user has tapped "My Picks" — list mode filters
    /// down to slots owned by `userStore.myUser`, board mode dims
    /// other columns instead of hiding them (keeps the spatial layout).
    @State private var myPicksOnly: Bool = false

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
        // Per-round override map: applies Sleeper's `traded_picks` to
        // each (round, slot) so a 2.05 traded from Reese to Luke
        // shows Luke in that cell, while Reese still owns 1.05 / 3.05.
        let teamsByRound = liveTeamsBySlotByRound(
            draft: draft,
            teamsBySlot: teamsBySlot,
            rounds: rounds
        )
        // Coordinate -> pick lookup, populated from polling. Keyed by
        // "round.slot" because Swift tuples don't conform to Hashable.
        let picksByCell: [String: DraftPick] = Dictionary(
            uniqueKeysWithValues: historyStore.upcomingPicks.map { pick in
                ("\(pick.round).\(pick.draftSlot)", pick)
            }
        )

        return VStack(spacing: 0) {
            controlsBar

            ScrollView {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                    liveHeaderCard(draft: draft, totalPicks: totalPicks, firstPick: firstPick)

                    switch viewMode {
                    case .rounds:
                        liveRoundsList(
                            rounds: rounds,
                            slots: slots,
                            teamsBySlot: teamsBySlot,
                            teamsByRound: teamsByRound,
                            picksByCell: picksByCell,
                            firstPick: firstPick,
                            myUserId: myUserId
                        )
                    case .board:
                        liveBoard(
                            rounds: rounds,
                            slots: slots,
                            teamsBySlot: teamsBySlot,
                            teamsByRound: teamsByRound,
                            picksByCell: picksByCell,
                            myUserId: myUserId
                        )
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        }
        .task(id: draft.draftId) {
            // Initial picks fetch + lightweight polling while the draft
            // is live. Polls every 5s when `drafting`, every 30s when
            // `pre_draft` (rare order changes), pauses when complete.
            await historyStore.refreshUpcomingPicks()
            while !Task.isCancelled {
                let interval: UInt64
                switch (draft.status ?? "").lowercased() {
                case "drafting":  interval = 5_000_000_000   // 5s
                case "pre_draft": interval = 30_000_000_000  // 30s
                default:          return                      // complete — stop polling
                }
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await historyStore.refreshUpcomingPicks()
            }
        }
    }

    // MARK: - Controls bar

    private var controlsBar: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            filterChip(label: "All Picks", selected: !myPicksOnly) { myPicksOnly = false }
            filterChip(label: "My Picks",  selected:  myPicksOnly) { myPicksOnly = true  }

            Spacer()

            viewModeToggle
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .background(XomperColors.bgDark)
    }

    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(.caption.weight(selected ? .bold : .regular))
                .foregroundStyle(selected ? XomperColors.bgDark : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, 6)
                .background(selected ? XomperColors.championGold : XomperColors.bgCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(DraftViewMode.allCases) { mode in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewMode = mode
                }) {
                    Image(systemName: mode.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(viewMode == mode ? XomperColors.bgDark : XomperColors.textSecondary)
                        .frame(width: 36, height: 28)
                        .background(viewMode == mode ? XomperColors.championGold : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
            }
        }
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
    }

    // MARK: - Rounds list

    private func liveRoundsList(
        rounds: Int,
        slots: [Int],
        teamsBySlot: [Int: UpcomingDraftTeam],
        teamsByRound: [Int: [Int: UpcomingDraftTeam]],
        picksByCell: [String: DraftPick],
        firstPick: Date?,
        myUserId: String?
    ) -> some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            ForEach(1...rounds, id: \.self) { round in
                let perRound = teamsByRound[round] ?? teamsBySlot
                let rowSlots = visibleSlots(for: round, slots: slots, teamsByRound: teamsByRound, teamsBySlot: teamsBySlot, myUserId: myUserId)
                if !rowSlots.isEmpty {
                    VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                        sectionHeader("Round \(round)")
                        ForEach(rowSlots, id: \.self) { slot in
                            let pickNo = (round - 1) * slots.count + slot
                            let team = perRound[slot]
                            let isMine = team?.userId != nil && team?.userId == myUserId
                            let pick = picksByCell["\(round).\(slot)"]
                            liveRichRow(
                                round: round,
                                slot: slot,
                                pickNo: pickNo,
                                team: team,
                                pick: pick,
                                isMine: isMine,
                                pickDate: pickDate(firstPick: firstPick, pickNo: pickNo)
                            )
                        }
                    }
                }
            }
        }
    }

    /// Filters slots to "mine only" when the toggle is on, otherwise
    /// returns the full slot list. Used by the rounds-list mode. Uses
    /// `teamsByRound[round]` so traded picks register as mine even
    /// when the slot's original owner isn't me.
    private func visibleSlots(
        for round: Int,
        slots: [Int],
        teamsByRound: [Int: [Int: UpcomingDraftTeam]],
        teamsBySlot: [Int: UpcomingDraftTeam],
        myUserId: String?
    ) -> [Int] {
        guard myPicksOnly, let myUserId else { return slots }
        let perRound = teamsByRound[round] ?? teamsBySlot
        return slots.filter { perRound[$0]?.userId == myUserId }
    }

    /// Single row that flips from "empty slot waiting" to "pick made"
    /// when the live polling lands a pick for this (round, slot).
    private func liveRichRow(
        round: Int,
        slot: Int,
        pickNo: Int,
        team: UpcomingDraftTeam?,
        pick: DraftPick?,
        isMine: Bool,
        pickDate: Date?
    ) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Text(String(format: "%d.%02d", round, slot))
                .font(.title3.weight(.bold))
                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textSecondary)
                .frame(width: 52, alignment: .leading)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                if let pick {
                    let first = pick.metadata?.firstName ?? ""
                    let last  = pick.metadata?.lastName  ?? ""
                    let name  = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                    Text(name.isEmpty ? "Pick made" : name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        if let pos = pick.metadata?.position {
                            Text(pos)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(XomperColors.bgDark)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(XomperColors.successGreen)
                                .clipShape(Capsule())
                        }
                        if let nfl = pick.metadata?.team {
                            Text(nfl)
                                .font(.caption2)
                                .foregroundStyle(XomperColors.textMuted)
                        }
                        Text("· \(team?.teamName ?? "Slot \(slot)")")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                            .lineLimit(1)
                    }
                } else {
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

    // MARK: - Board grid

    private func liveBoard(
        rounds: Int,
        slots: [Int],
        teamsBySlot: [Int: UpcomingDraftTeam],
        teamsByRound: [Int: [Int: UpcomingDraftTeam]],
        picksByCell: [String: DraftPick],
        myUserId: String?
    ) -> some View {
        let cellWidth: CGFloat = 92
        let cellHeight: CGFloat = 70
        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                // Column header — slot number + team name.
                HStack(spacing: 6) {
                    Text("R")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                        .frame(width: 22)
                    ForEach(slots, id: \.self) { slot in
                        let team = teamsBySlot[slot]
                        let isMine = team?.userId != nil && team?.userId == myUserId
                        VStack(spacing: 1) {
                            Text("\(slot)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textMuted)
                            Text(team?.teamName ?? "—")
                                .font(.caption2)
                                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(width: cellWidth, alignment: .center)
                    }
                }

                ForEach(1...rounds, id: \.self) { round in
                    let perRound = teamsByRound[round] ?? teamsBySlot
                    HStack(spacing: 6) {
                        Text("\(round)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(XomperColors.championGold)
                            .frame(width: 22)
                        ForEach(slots, id: \.self) { slot in
                            let team = perRound[slot]
                            let isMine = team?.userId != nil && team?.userId == myUserId
                            liveBoardCell(
                                round: round,
                                slot: slot,
                                team: team,
                                pick: picksByCell["\(round).\(slot)"],
                                isMine: isMine,
                                width: cellWidth,
                                height: cellHeight
                            )
                        }
                    }
                }
            }
        }
    }

    private func liveBoardCell(
        round: Int,
        slot: Int,
        team: UpcomingDraftTeam?,
        pick: DraftPick?,
        isMine: Bool,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pick {
                let first = pick.metadata?.firstName ?? ""
                let last = pick.metadata?.lastName ?? ""
                let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                Text(name.isEmpty ? "Picked" : name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    if let pos = pick.metadata?.position {
                        Text(pos)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(XomperColors.bgDark)
                            .padding(.horizontal, 4)
                            .background(XomperColors.successGreen)
                            .clipShape(Capsule())
                    }
                    if let nfl = pick.metadata?.team {
                        Text(nfl)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textSecondary)
                    }
                }
            } else {
                Text(team?.teamName ?? "Slot \(slot)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(XomperColors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(String(format: "%d.%02d", round, slot))
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }
            if isMine && pick == nil {
                Text("YOU")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
            }
        }
        .padding(6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(pick == nil ? XomperColors.bgCard : XomperColors.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(
                    isMine ? XomperColors.championGold.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
        // Dim non-mine cells when the user has flipped on My Picks.
        // Board view doesn't hide other slots (the spatial layout is
        // half the point), but the dim keeps focus on the user's
        // column without breaking the grid.
        .opacity(myPicksOnly && !isMine ? 0.25 : 1.0)
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

    /// Expands the slot→team map across every round, swapping in the
    /// new owner for any (round, originalRoster) that's been traded.
    /// Sleeper's `traded_picks` records the chain in a flat list keyed
    /// by the ORIGINAL roster (not slot); we map slot → originalRoster
    /// via `upcomingRosters`, then walk `upcomingTradedPicks` to find
    /// the current owner for each round. Untraded picks fall through
    /// to the base `teamsBySlot` mapping.
    private func liveTeamsBySlotByRound(
        draft: Draft,
        teamsBySlot: [Int: UpcomingDraftTeam],
        rounds: Int
    ) -> [Int: [Int: UpcomingDraftTeam]] {
        // userId -> team (for assembling the override entry).
        var teamByUser: [String: UpcomingDraftTeam] = [:]
        for user in historyStore.upcomingUsers {
            guard let userId = user.userId else { continue }
            teamByUser[userId] = UpcomingDraftTeam(
                userId: userId,
                teamName: user.teamName ?? user.resolvedDisplayName,
                avatarId: user.avatar
            )
        }
        // ownerId (the Sleeper roster ownerId is a userId string) -> rosterId
        // and the inverse so we can hop slot → roster → user.
        var rosterIdByUserId: [String: Int] = [:]
        var userIdByRosterId: [Int: String] = [:]
        for roster in historyStore.upcomingRosters {
            guard let ownerId = roster.ownerId else { continue }
            rosterIdByUserId[ownerId] = roster.rosterId
            userIdByRosterId[roster.rosterId] = ownerId
        }
        // Trade lookup keyed by "round.originalRosterId" -> current ownerId roster.
        let season = draft.season
        var tradesByRoundAndRoster: [String: Int] = [:]
        for tp in historyStore.upcomingTradedPicks where tp.season == season {
            tradesByRoundAndRoster["\(tp.round).\(tp.rosterId)"] = tp.ownerId
        }

        var out: [Int: [Int: UpcomingDraftTeam]] = [:]
        for round in 1...max(rounds, 1) {
            var row: [Int: UpcomingDraftTeam] = [:]
            for (slot, originalTeam) in teamsBySlot {
                // Slot's original-owner roster, used to look up trades.
                let originalRoster = rosterIdByUserId[originalTeam.userId]
                if let origRoster = originalRoster,
                   let newOwnerRoster = tradesByRoundAndRoster["\(round).\(origRoster)"],
                   let newOwnerUserId = userIdByRosterId[newOwnerRoster],
                   let newOwnerTeam = teamByUser[newOwnerUserId] {
                    row[slot] = newOwnerTeam
                } else {
                    row[slot] = originalTeam
                }
            }
            out[round] = row
        }
        return out
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
