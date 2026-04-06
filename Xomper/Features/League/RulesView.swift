import SwiftUI

struct RulesView: View {
    var league: League
    var rulesStore: RulesStore
    var authStore: AuthStore

    @State private var showProposalForm = false
    @State private var expandedRuleSections: Set<Int> = []

    private var totalRosters: Int { league.totalRosters }
    private var leagueName: String { league.displayName }
    private var leagueId: String { league.leagueId }

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                scoringSettingsSection
                rosterSlotsSection
                leagueSettingsSection
                proposalsSection
                leagueRulebookSection
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark)
        .refreshable {
            await rulesStore.loadProposals(leagueId: leagueId, totalRosters: totalRosters)
        }
        .sheet(isPresented: $showProposalForm) {
            RuleProposalFormView(
                rulesStore: rulesStore,
                leagueId: leagueId,
                leagueName: leagueName,
                proposerName: resolvedProposerName,
                totalRosters: totalRosters,
                isPresented: $showProposalForm
            )
        }
        .task {
            if rulesStore.proposals.isEmpty {
                await rulesStore.loadProposals(leagueId: leagueId, totalRosters: totalRosters)
            }
        }
    }

    // MARK: - Proposer Name

    private var resolvedProposerName: String {
        authStore.userDisplayName
            ?? authStore.sleeperUsername
            ?? authStore.userEmail?.components(separatedBy: "@").first
            ?? "A league member"
    }

    private var currentUserId: String? {
        try? authStore.session?.user.id.uuidString
    }
}

// MARK: - Scoring Settings

private extension RulesView {

    var scoringSettingsSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            sectionTitle("Scoring Settings")

            let categories = buildScoringCategories()
            if categories.isEmpty {
                Text("No scoring settings available.")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textMuted)
            } else {
                ForEach(categories, id: \.name) { category in
                    ScoringCategoryCard(category: category)
                }
            }
        }
    }

    func buildScoringCategories() -> [ScoringCategory] {
        guard let scoring = league.scoringSettings else { return [] }

        let categoryDefs: [(name: String, prefixes: [String])] = [
            ("Passing", ["pass_"]),
            ("Rushing", ["rush_"]),
            ("Receiving", ["rec", "bonus_rec"]),
            ("Return TDs", ["pr_", "kr_"]),
            ("Fumbles", ["fum"]),
            ("Kicking", ["fg_", "xp"]),
        ]

        var usedKeys = Set<String>()
        var result: [ScoringCategory] = []

        for def in categoryDefs {
            let settings = scoring
                .filter { key, _ in
                    def.prefixes.contains(where: { key.hasPrefix($0) }) && !usedKeys.contains(key)
                }
                .map { key, value -> ScoringEntry in
                    usedKeys.insert(key)
                    return ScoringEntry(key: key, label: Self.scoringKeyLabel(key), value: value)
                }
                .filter { $0.value != 0 }
                .sorted { abs($0.value) > abs($1.value) }

            if !settings.isEmpty {
                result.append(ScoringCategory(name: def.name, settings: settings))
            }
        }

        return result
    }

    static func scoringKeyLabel(_ key: String) -> String {
        let labels: [String: String] = [
            "pass_yd": "Pass Yards",
            "pass_td": "Pass TD",
            "pass_int": "Interception",
            "pass_2pt": "Pass 2PT",
            "pass_att": "Pass Attempts",
            "pass_cmp": "Completions",
            "pass_inc": "Incompletions",
            "rush_yd": "Rush Yards",
            "rush_td": "Rush TD",
            "rush_2pt": "Rush 2PT",
            "rush_att": "Rush Attempts",
            "rec": "Receptions",
            "rec_yd": "Rec Yards",
            "rec_td": "Rec TD",
            "rec_2pt": "Rec 2PT",
            "bonus_rec_te": "TE Premium",
            "bonus_rec_wr": "WR Bonus",
            "bonus_rec_rb": "RB Rec Bonus",
            "bonus_rush_yd_100": "100+ Rush Yds",
            "bonus_rec_yd_100": "100+ Rec Yds",
            "bonus_pass_yd_300": "300+ Pass Yds",
            "pr_td": "Punt Return TD",
            "kr_td": "Kick Return TD",
            "fum": "Fumble",
            "fum_lost": "Fumble Lost",
            "fum_rec": "Fumble Recovery",
            "fum_rec_td": "Fumble Rec TD",
            "fg_0_19": "FG 0-19",
            "fg_20_29": "FG 20-29",
            "fg_30_39": "FG 30-39",
            "fg_40_49": "FG 40-49",
            "fg_50p": "FG 50+",
            "fg_miss": "FG Miss",
            "fg_miss_0_19": "FG Miss 0-19",
            "fg_miss_20_29": "FG Miss 20-29",
            "fg_miss_30_39": "FG Miss 30-39",
            "fg_miss_40_49": "FG Miss 40-49",
            "fg_miss_50p": "FG Miss 50+",
            "xpm": "XP Made",
            "xpmiss": "XP Missed",
        ]

        if let label = labels[key] { return label }

        // Fallback: format key as title case
        return key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Roster Slots

private extension RulesView {

    var rosterSlotsSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            sectionTitle("Roster Slots")

            let slots = buildRosterSlots()
            if slots.isEmpty {
                Text("No roster configuration available.")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textMuted)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 64), spacing: XomperTheme.Spacing.sm)],
                    spacing: XomperTheme.Spacing.sm
                ) {
                    ForEach(slots, id: \.position) { slot in
                        RosterSlotBadge(slot: slot)
                    }
                }
            }
        }
    }

    func buildRosterSlots() -> [RosterSlot] {
        guard let positions = league.rosterPositions else { return [] }

        var counts: [(position: String, count: Int)] = []
        var seen: [String: Int] = [:] // position -> index in counts

        for pos in positions where pos != "BN" {
            if let index = seen[pos] {
                counts[index].count += 1
            } else {
                seen[pos] = counts.count
                counts.append((pos, 1))
            }
        }

        let benchCount = positions.filter { $0 == "BN" }.count
        if benchCount > 0 {
            counts.append(("BN", benchCount))
        }

        return counts.map { RosterSlot(position: $0.position, count: $0.count) }
    }
}

// MARK: - League Settings

private extension RulesView {

    var leagueSettingsSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            sectionTitle("League Settings")

            let settings = buildLeagueSettings()
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: XomperTheme.Spacing.sm),
                    GridItem(.flexible(), spacing: XomperTheme.Spacing.sm)
                ],
                spacing: XomperTheme.Spacing.sm
            ) {
                ForEach(settings, id: \.label) { setting in
                    LeagueSettingCard(label: setting.label, value: setting.value)
                }
            }
        }
    }

    func buildLeagueSettings() -> [(label: String, value: String)] {
        [
            ("Format", league.isDynasty ? "Dynasty" : "Redraft"),
            ("Teams", "\(league.totalRosters)"),
            ("Playoff Teams", "\(league.settings.playoffTeams ?? 6)"),
            ("Taxi Slots", "\(league.settings.taxiSlots ?? 0)"),
            ("Trade Deadline", "Week \(league.settings.tradeDeadline.map(String.init) ?? "N/A")"),
            ("Divisions", "\(league.divisions.count)"),
        ]
    }
}

// MARK: - Proposals Section

private extension RulesView {

    var proposalsSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            proposalsHeader
            proposalFilterPicker
            proposalsList
        }
    }

    var proposalsHeader: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack {
                sectionTitle("Rule Proposals")
                Spacer()
                proposeButton
            }

            Text("\(rulesStore.approvalThreshold(totalRosters: totalRosters))/\(totalRosters) votes to approve")
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)
        }
    }

    var proposeButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showProposalForm = true
        } label: {
            Label("Propose", systemImage: "plus.circle.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.deepNavy)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(XomperColors.championGold)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Propose a new rule")
    }

    var proposalFilterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                ForEach(ProposalFilter.allCases) { filter in
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(XomperTheme.defaultAnimation) {
                            rulesStore.proposalFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption)
                            .fontWeight(rulesStore.proposalFilter == filter ? .semibold : .regular)
                            .foregroundStyle(
                                rulesStore.proposalFilter == filter
                                    ? XomperColors.deepNavy
                                    : XomperColors.textSecondary
                            )
                            .padding(.horizontal, XomperTheme.Spacing.md)
                            .padding(.vertical, XomperTheme.Spacing.xs)
                            .frame(minHeight: XomperTheme.minTouchTarget)
                            .background(
                                rulesStore.proposalFilter == filter
                                    ? XomperColors.championGold
                                    : XomperColors.surfaceLight
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(filter.rawValue) proposals")
                    .accessibilityAddTraits(rulesStore.proposalFilter == filter ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    var proposalsList: some View {
        let proposals = rulesStore.filteredProposals

        if rulesStore.isLoading {
            LoadingView(message: "Loading proposals...")
        } else if proposals.isEmpty {
            emptyProposalsView
        } else {
            LazyVStack(spacing: XomperTheme.Spacing.md) {
                ForEach(proposals) { proposal in
                    ProposalCardView(
                        proposal: proposal,
                        totalRosters: totalRosters,
                        currentUserId: currentUserId,
                        isRecentlyStamped: rulesStore.recentlyStampedIds.contains(proposal.id),
                        onVote: { vote in
                            Task {
                                _ = await rulesStore.castVote(
                                    proposalId: proposal.id,
                                    vote: vote,
                                    leagueId: leagueId,
                                    leagueName: leagueName,
                                    totalRosters: totalRosters
                                )
                            }
                        },
                        onDelete: {
                            Task {
                                _ = await rulesStore.deleteProposal(
                                    proposalId: proposal.id,
                                    leagueId: leagueId,
                                    totalRosters: totalRosters
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    var emptyProposalsView: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(XomperColors.textMuted)

            if rulesStore.proposals.isEmpty {
                Text("No proposals yet. Be the first to suggest a rule change!")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No \(rulesStore.proposalFilter.rawValue.lowercased()) proposals.")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XomperTheme.Spacing.lg)
    }
}

// MARK: - League Rulebook

private extension RulesView {

    var leagueRulebookSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            sectionTitle("League Rulebook")

            ForEach(Array(Self.leagueRules.enumerated()), id: \.offset) { index, rule in
                RulebookChapterView(
                    title: rule.title,
                    content: rule.content,
                    isExpanded: expandedRuleSections.contains(index),
                    onToggle: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(XomperTheme.defaultAnimation) {
                            if expandedRuleSections.contains(index) {
                                expandedRuleSections.remove(index)
                            } else {
                                expandedRuleSections.insert(index)
                            }
                        }
                    }
                )
            }
        }
    }

    static let leagueRules: [(title: String, content: String)] = [
        (
            "1. League Setup",
            """
            A. Divisions
            Three divisions of 4. Divisions are set for four years then reset based on standings in the fourth year regular season.

            Division realignment by finish:
            ACC: #1 (Winner), #6, #7, #12 (Last)
            SEC: #2, #5, #8, #11
            Big 10: #3, #4, #9, #10

            World Cup Tournament
            Every four years there is a season-long in-season tournament. Top 2 teams from each division over the first 3 years compete in a 6-team tournament during the 4th year. Only intra-divisional games count. Tiebreaker: overall record, then H2H, then total points.

            Rounds:
            Round 1: Total points weeks 3-6. Top 4 advance.
            Round 2: #1 vs #4, #2 vs #3. Aggregate points weeks 7-10.
            Round 3: Winners aggregate points weeks 11-14.

            B. Fantasy Host Site -- Sleeper.app
            """
        ),
        (
            "2. Schedule & Season Format",
            """
            A. Regular Season
            Week 14 is the last week of the regular season.

            B. Playoffs
            Playoffs begin Week 15 and end Week 17 (1-week matchups). In a tie, the higher seed wins. 6 teams make the playoffs: top team from each division seeded 1-3, plus 3 wild card spots. Overall record determines standings; tiebreaker is total points for.

            No consolation games or 3rd place match. Eliminated teams are ranked by seed at time of elimination.

            C. Offseason
            No free agency adds during offseason -- only via Rookie/FA draft. Trading of players and picks is allowed. Roster cuts due by midnight the Sunday after NFL preseason concludes.
            """
        ),
        (
            "3. Roster Rules, Trading & Add/Drops",
            """
            A. Roster Sizes -- 26 active + 4 taxi + 8 IR

            B. Starting Requirements
            1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX (RB/WR/TE), 1 SUPERFLEX (QB/RB/WR/TE)

            No purposely starting bye/injured/inactive players to tank. Active players must be used. $5 penalty for playing an inactive player while tanking (goes to winner's pot).

            C. Taxi Squad Steals
            Teams can steal another team's taxi player with draft pick compensation:
            1st Round Taken -> 1st + 2nd round pick
            2nd Round Taken -> 1st round pick
            3rd Round Taken -> 2nd round pick
            4th Round Taken -> 3rd round pick
            5th Round Taken -> 4th round pick
            Undrafted -> 5th round pick

            Owner can promote the taxi player before Thursday 12pm EST to nullify the steal.

            D. Injured Reserve -- 8 IR slots per team.

            E. Trading
            Trades can be uneven. Rosters must be adjusted to 26 active immediately. Vetoes require unanimous vote with evidence of collusion. Picks up to 2 years out can be traded.

            F. Trade Deadline -- 2 weeks after NFL trade deadline (Tuesday after Week 10 at noon).

            G. Add/Drops -- Deadline at conclusion of regular season. No adds once the first game of the week starts.

            H. Roster Cuts -- By midnight Sunday after NFL preseason. Max: 26 active + 4 taxi + 8 IR = 38 total.

            I. Waivers -- Dropped players clear waivers by Wednesday morning. Waiver order does not reset; claiming moves you to the back.
            """
        ),
        (
            "4. Scoring",
            """
            QB, RB, WR, TE Scoring:
            Passing TD: 4 pts
            Passing Yards: 1 per 25 yds (0.04/yd)
            Interception Thrown: -2 pts
            Pass 2PT Conversion: 2 pts
            Rushing TD: 6 pts
            Rushing Yards: 1 per 10 yds (0.1/yd)
            Rush 2PT Conversion: 2 pts
            Receiving TD: 6 pts
            Receiving Yards: 1 per 10 yds (0.1/yd)
            Receptions (PPR): 1 pt (TE: 1.5 pts)
            Rec 2PT Conversion: 2 pts
            Punt/Kick Return TD: 6 pts
            Fumble Lost: -2 pts
            """
        ),
        (
            "5. Draft Information",
            """
            A. Startup Draft -- Snake draft, order randomized.

            B. Rookie Draft
            Not a snake draft. Last place gets 1.01, 2.01, 3.01, 4.01, 5.01. Picks are tradeable. Any free agents not added before the championship add/drop deadline are also eligible.

            C. Draft Order
            Non-playoff teams: determined by overall record.
            Playoff teams: determined by playoff performance. Eliminated teams with worse seeds get better picks.
            """
        ),
        (
            "6. Dues & Payouts",
            """
            A. Dues -- $100 per season.

            B. Payout Structure:
            Champion: $600
            2nd Place: $200
            3rd Place: $80
            4th Place: $80
            Highest Weekly Score (x14): $10 each
            World Cup Winner (every 4 yrs): $400

            MVP awards for positional leaders (player must have been started that week to count).
            """
        ),
        (
            "7. Rule Changes",
            """
            2/3 Vote Required
            Rule change voting occurs in the offseason. At least 8 owners (of 12) must vote in favor for a rule change to become permanent.

            A 100% unanimous vote can enact a rule effective immediately.
            """
        ),
    ]
}

// MARK: - Section Title Helper

private extension RulesView {
    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .fontWeight(.bold)
            .foregroundStyle(XomperColors.textPrimary)
    }
}

// MARK: - Scoring Category Card

private struct ScoringCategoryCard: View {
    let category: ScoringCategory

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text(category.name)
                .font(.headline)
                .foregroundStyle(XomperColors.championGold)

            ForEach(category.settings, id: \.key) { entry in
                HStack {
                    Text(entry.label)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                    Spacer()
                    Text(formattedValue(entry.value))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(entry.value > 0 ? XomperColors.successGreen : XomperColors.errorRed)
                }
            }
        }
        .xomperCard()
    }

    private func formattedValue(_ value: Double) -> String {
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
        return value > 0 ? "+\(formatted)" : formatted
    }
}

// MARK: - Roster Slot Badge

private struct RosterSlotBadge: View {
    let slot: RosterSlot

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.xxs) {
            Text(slot.position == "SUPER_FLEX" ? "SF" : slot.position)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(XomperColors.textPrimary)

            if slot.count > 1 {
                Text("x\(slot.count)")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
        .frame(minWidth: 48, minHeight: XomperTheme.minTouchTarget)
        .background(XomperColors.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }
}

// MARK: - League Setting Card

private struct LeagueSettingCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xomperCard()
    }
}

// MARK: - Proposal Card

private struct ProposalCardView: View {
    let proposal: RuleProposal
    let totalRosters: Int
    let currentUserId: String?
    let isRecentlyStamped: Bool
    let onVote: (VoteChoice) -> Void
    let onDelete: () -> Void

    @State private var showVoters = false

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            headerRow
            titleAndDescription
            authorRow
            voteProgressBar
            voteButtons
        }
        .xomperCard()
        .overlay(stampOverlay)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            statusBadge
            Spacer()
            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)

            if proposal.proposedBy == currentUserId && proposal.status == .open {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(XomperColors.textMuted)
                        .frame(minWidth: XomperTheme.minTouchTarget, minHeight: XomperTheme.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete proposal")
            }
        }
    }

    private var statusBadge: some View {
        Text(proposal.status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(statusColor)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xxs)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch proposal.status {
        case .open: XomperColors.steelBlue
        case .approved: XomperColors.successGreen
        case .rejected: XomperColors.errorRed
        case .closed: XomperColors.textMuted
        }
    }

    // MARK: - Title & Description

    private var titleAndDescription: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text(proposal.title)
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)

            if !proposal.description.isEmpty {
                Text(proposal.description)
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var authorRow: some View {
        Text("Proposed by \(proposal.proposedByUsername)")
            .font(.caption)
            .foregroundStyle(XomperColors.textMuted)
    }

    // MARK: - Vote Progress

    @ViewBuilder
    private var voteProgressBar: some View {
        if proposal.totalVotes > 0 {
            VStack(spacing: XomperTheme.Spacing.xs) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(XomperColors.successGreen)
                            .frame(width: geo.size.width * yesPercentage)

                        Rectangle()
                            .fill(XomperColors.errorRed)
                            .frame(width: geo.size.width * noPercentage)

                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .background(XomperColors.surfaceLight.clipShape(Capsule()))

                HStack {
                    Text("\(proposal.yesCount) Yes")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.successGreen)
                    Spacer()
                    Text("\(proposal.noCount) No")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.errorRed)
                }
            }
        }
    }

    private var yesPercentage: Double {
        guard totalRosters > 0 else { return 0 }
        return Double(proposal.yesCount) / Double(totalRosters)
    }

    private var noPercentage: Double {
        guard totalRosters > 0 else { return 0 }
        return Double(proposal.noCount) / Double(totalRosters)
    }

    // MARK: - Vote Buttons

    @ViewBuilder
    private var voteButtons: some View {
        if proposal.status == .open {
            HStack(spacing: XomperTheme.Spacing.sm) {
                voteButton(choice: .yes)
                voteButton(choice: .no)
            }
        }
    }

    private func voteButton(choice: VoteChoice) -> some View {
        let isVoted = proposal.myVote == choice
        let isYes = choice == .yes
        let label = isVoted
            ? (isYes ? "Voted Yes" : "Voted No")
            : (isYes ? "Vote Yes" : "Vote No")
        let color = isYes ? XomperColors.successGreen : XomperColors.errorRed

        return Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onVote(choice)
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isVoted ? XomperColors.deepNavy : color)
                .frame(maxWidth: .infinity)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(isVoted ? color : color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Stamp Overlay

    @ViewBuilder
    private var stampOverlay: some View {
        if proposal.status == .approved || proposal.status == .rejected {
            let isApproved = proposal.status == .approved
            Text(isApproved ? "APPROVED" : "DENIED")
                .font(.title2)
                .fontWeight(.black)
                .foregroundStyle(
                    (isApproved ? XomperColors.successGreen : XomperColors.errorRed).opacity(0.25)
                )
                .rotationEffect(.degrees(-15))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: String(proposal.createdAt.prefix(19))) {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
        return proposal.createdAt
    }
}

// MARK: - Rulebook Chapter

private struct RulebookChapterView: View {
    let title: String
    let content: String
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(XomperColors.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(minHeight: XomperTheme.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")

            if isExpanded {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, XomperTheme.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .xomperCard()
    }
}

// MARK: - Supporting Types

private struct ScoringCategory {
    let name: String
    let settings: [ScoringEntry]
}

private struct ScoringEntry {
    let key: String
    let label: String
    let value: Double
}

private struct RosterSlot {
    let position: String
    let count: Int
}
