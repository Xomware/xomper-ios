import SwiftUI

/// Standalone two-team trade builder.
///
/// Unlike the Team Analyzer's Trade tab — which anchors Side A to *your*
/// team and Side B to a chosen partner — this page lets you pick ANY two
/// teams in the league and construct a hypothetical trade between them.
/// Useful for evaluating deals you're not part of (commissioner review,
/// "should they have done that?" debates) or war-gaming a package before
/// you approach a partner.
///
/// Reuses:
/// - `PlayerValuesStore` — FantasyCalc dynasty superflex values
/// - `TradeEvaluator` — the same pure evaluation used by the Trade tab
/// - `TeamAnalysisBuilder` — to enumerate teams (name + total value)
/// - `TradeSidePickerContext` — the shared player/pick picker context
struct TradeAnalysisView: View {
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var valuesStore: PlayerValuesStore
    var tradedPicks: [TradedPick] = []

    // MARK: - Builder state
    //
    // Local `@State` (not the shared `TradeAnalyzerController`) — this
    // page is any-team-vs-any-team, so it has no "my side" semantics to
    // seed and nothing else deep-links into it.

    @State private var teamARosterId: Int?
    @State private var teamBRosterId: Int?
    @State private var sideAPlayerIds: [String] = []
    @State private var sideAPickNames: [String] = []
    @State private var sideBPlayerIds: [String] = []
    @State private var sideBPickNames: [String] = []

    @State private var showSidePicker: TradeSidePickerContext?

    var body: some View {
        Group {
            if !valuesStore.hasValues && valuesStore.isLoading {
                LoadingView(message: "Fetching player values...")
            } else if let error = valuesStore.error, !valuesStore.hasValues {
                ErrorView(message: error.localizedDescription) {
                    Task { await valuesStore.loadValues(forceRefresh: true) }
                }
            } else if !valuesStore.hasValues {
                EmptyStateView(
                    icon: "arrow.left.arrow.right.circle",
                    title: "Values Not Loaded",
                    message: "Pull to refresh to load dynasty values."
                )
            } else if leagueStore.myLeagueRosters.isEmpty {
                LoadingView(message: "Loading league...")
            } else {
                content
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task {
            await valuesStore.loadValues()
        }
        .refreshable {
            await valuesStore.loadValues(forceRefresh: true)
        }
    }

    // MARK: - Content

    private var content: some View {
        let analyses = TeamAnalysisBuilder.build(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            valuesStore: valuesStore
        )
        let teamA = analyses.first { $0.rosterId == teamARosterId }
        let teamB = analyses.first { $0.rosterId == teamBRosterId }
        let trade = currentTrade(teamA: teamA, teamB: teamB)
        let evaluation = TradeEvaluator.evaluate(trade, valuesStore: valuesStore)

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                explainer

                teamPickers(analyses: analyses)

                if teamA != nil && teamB != nil {
                    evaluationStrip(
                        evaluation: evaluation,
                        teamAName: teamA?.teamName ?? "Team A",
                        teamBName: teamB?.teamName ?? "Team B"
                    )

                    if let teamA {
                        sideCard(
                            sideLabel: "\(teamA.teamName) sends",
                            teamName: teamA.teamName,
                            playerIds: sideAPlayerIds,
                            pickNames: sideAPickNames,
                            sideValue: evaluation.sideAValue,
                            addAction: {
                                showSidePicker = TradeSidePickerContext(
                                    side: .a, kind: .player,
                                    rosterId: teamA.rosterId, teamName: teamA.teamName
                                )
                            },
                            removePlayerAction: { pid in
                                sideAPlayerIds.removeAll { $0 == pid }
                            },
                            removePickAction: { name in
                                sideAPickNames.removeAll { $0 == name }
                            }
                        )
                    }

                    if let teamB {
                        sideCard(
                            sideLabel: "\(teamB.teamName) sends",
                            teamName: teamB.teamName,
                            playerIds: sideBPlayerIds,
                            pickNames: sideBPickNames,
                            sideValue: evaluation.sideBValue,
                            addAction: {
                                showSidePicker = TradeSidePickerContext(
                                    side: .b, kind: .player,
                                    rosterId: teamB.rosterId, teamName: teamB.teamName
                                )
                            },
                            removePlayerAction: { pid in
                                sideBPlayerIds.removeAll { $0 == pid }
                            },
                            removePickAction: { name in
                                sideBPickNames.removeAll { $0 == name }
                            }
                        )
                    }

                    if !trade.isEmpty {
                        Button(role: .destructive) {
                            sideAPlayerIds = []
                            sideBPlayerIds = []
                            sideAPickNames = []
                            sideBPickNames = []
                        } label: {
                            Text("Clear trade")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(XomperColors.errorRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, XomperTheme.Spacing.sm)
                        }
                        .buttonStyle(.pressableCard)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                    }
                } else {
                    pickTeamsHint
                }
            }
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
        .sheet(item: $showSidePicker) { context in
            NavigationStack {
                sidePicker(context: context)
            }
            .presentationDetents([.large])
        }
    }

    private func currentTrade(teamA: TeamAnalysis?, teamB: TeamAnalysis?) -> ProposedTrade {
        ProposedTrade(
            sideA: TradeSide(
                rosterId: teamA?.rosterId ?? 0,
                teamName: teamA?.teamName ?? "",
                playerIds: sideAPlayerIds,
                pickNames: sideAPickNames
            ),
            sideB: TradeSide(
                rosterId: teamB?.rosterId ?? 0,
                teamName: teamB?.teamName ?? "",
                playerIds: sideBPlayerIds,
                pickNames: sideBPickNames
            )
        )
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(XomperColors.championGold)
                Text("Trade analysis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }
            Text("Pick any two teams, then drop in players or draft picks from each side. Live FantasyCalc value totals, the winner, the value differential, and the percentage gap update on every change.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private var pickTeamsHint: some View {
        Text("Pick a team on each side to start building a trade.")
            .font(.caption)
            .foregroundStyle(XomperColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, XomperTheme.Spacing.lg)
            .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Team pickers

    private func teamPickers(analyses: [TeamAnalysis]) -> some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            teamPickerRow(
                label: "Team A",
                selectedRosterId: teamARosterId,
                candidates: analyses.filter { $0.rosterId != teamBRosterId },
                onSelect: { rosterId in
                    if teamARosterId != rosterId {
                        sideAPlayerIds = []
                        sideAPickNames = []
                    }
                    teamARosterId = rosterId
                },
                onClear: {
                    teamARosterId = nil
                    sideAPlayerIds = []
                    sideAPickNames = []
                }
            )

            teamPickerRow(
                label: "Team B",
                selectedRosterId: teamBRosterId,
                candidates: analyses.filter { $0.rosterId != teamARosterId },
                onSelect: { rosterId in
                    if teamBRosterId != rosterId {
                        sideBPlayerIds = []
                        sideBPickNames = []
                    }
                    teamBRosterId = rosterId
                },
                onClear: {
                    teamBRosterId = nil
                    sideBPlayerIds = []
                    sideBPickNames = []
                }
            )
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func teamPickerRow(
        label: String,
        selectedRosterId: Int?,
        candidates: [TeamAnalysis],
        onSelect: @escaping (Int) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        let sorted = candidates.sorted { $0.totalValue > $1.totalValue }
        let selectedName = sorted.first { $0.rosterId == selectedRosterId }?.teamName

        return HStack(spacing: XomperTheme.Spacing.sm) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textSecondary)
                .frame(width: 64, alignment: .leading)

            Menu {
                Button("None") { onClear() }
                Divider()
                ForEach(sorted, id: \.rosterId) { team in
                    Button {
                        onSelect(team.rosterId)
                    } label: {
                        HStack {
                            Text(team.teamName)
                            Spacer()
                            Text("\(team.totalValue)")
                                .monospacedDigit()
                        }
                    }
                }
            } label: {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Text(selectedName ?? "Pick team")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedName == nil ? XomperColors.textSecondary : XomperColors.bgDark)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedName == nil ? XomperColors.textSecondary : XomperColors.bgDark)
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedName == nil ? XomperColors.surfaceLight.opacity(0.4) : Color.cyan)
                .clipShape(Capsule())
            }
            .accessibilityLabel(selectedName.map { "\(label): \($0)" } ?? "Pick \(label)")
        }
    }

    // MARK: - Evaluation strip

    private func evaluationStrip(
        evaluation: TradeEvaluation,
        teamAName: String,
        teamBName: String
    ) -> some View {
        let pillColor: Color = {
            switch evaluation.verdict {
            case .empty:    return XomperColors.surfaceLight.opacity(0.4)
            case .fair:     return XomperColors.successGreen
            case .sideAWins, .sideBWins: return XomperColors.errorRed.opacity(0.85)
            }
        }()

        let verdictLabel: String = {
            switch evaluation.verdict {
            case .empty:
                return "Add players to evaluate"
            case .fair:
                return "Even trade (within 5%)"
            case .sideAWins(let pct):
                return String(format: "%@ wins by %.0f%%", teamAName, pct * 100)
            case .sideBWins(let pct):
                return String(format: "%@ wins by %.0f%%", teamBName, pct * 100)
            }
        }()

        return VStack(spacing: XomperTheme.Spacing.sm) {
            HStack(alignment: .top) {
                valueColumn(label: teamAName, value: evaluation.sideAValue)
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(XomperColors.textMuted)
                Spacer()
                valueColumn(label: teamBName, value: evaluation.sideBValue)
            }

            Text(verdictLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(evaluation.verdict.isFair ? XomperColors.bgDark : .white)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .background(pillColor)
                .clipShape(Capsule())

            if evaluation.verdict.isEvaluable {
                HStack {
                    differentialColumn(
                        label: "Differential",
                        value: "\(abs(evaluation.delta))"
                    )
                    Spacer()
                    differentialColumn(
                        label: "Value gap",
                        value: String(format: "%.1f%%", evaluation.percentGap * 100)
                    )
                }
                .padding(.top, 2)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func valueColumn(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
                .lineLimit(1)
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func differentialColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Side card

    private func sideCard(
        sideLabel: String,
        teamName: String,
        playerIds: [String],
        pickNames: [String],
        sideValue: Int,
        addAction: @escaping () -> Void,
        removePlayerAction: @escaping (String) -> Void,
        removePickAction: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack {
                Text(sideLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(sideValue)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()
            }

            if playerIds.isEmpty && pickNames.isEmpty {
                Text("No players or picks added yet.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .padding(.vertical, XomperTheme.Spacing.xs)
            } else {
                ForEach(playerIds, id: \.self) { pid in
                    playerRow(pid: pid, removeAction: { removePlayerAction(pid) })
                }
                ForEach(pickNames, id: \.self) { name in
                    pickRow(name: name, removeAction: { removePickAction(name) })
                }
            }

            Button(action: addAction) {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add player or pick")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.bgDark)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 36)
                .background(XomperColors.championGold)
                .clipShape(Capsule())
            }
            .buttonStyle(.pressableCard)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func playerRow(pid: String, removeAction: @escaping () -> Void) -> some View {
        let player = playerStore.player(for: pid)
        let value = valuesStore.value(for: pid)
        return HStack(spacing: XomperTheme.Spacing.sm) {
            Text(player?.fullDisplayName ?? "Player #\(pid)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
            Text(player?.displayPosition ?? "")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(XomperColors.textMuted)
            }
            .buttonStyle(.pressableCard)
        }
        .padding(.vertical, 2)
    }

    private func pickRow(name: String, removeAction: @escaping () -> Void) -> some View {
        let value = valuesStore.pickValue(for: name)
        return HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "ticket.fill")
                .foregroundStyle(XomperColors.championGold)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
            Text("PICK")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(XomperColors.textMuted)
            }
            .buttonStyle(.pressableCard)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Picker sheet

    private func sidePicker(context: TradeSidePickerContext) -> some View {
        TradeItemPickerSheet(
            teamName: context.teamName,
            items: pickerItems(for: context),
            onSelect: { item in
                switch (context.side, item.kind) {
                case (.a, .player): sideAPlayerIds.append(item.id)
                case (.b, .player): sideBPlayerIds.append(item.id)
                case (.a, .pick): sideAPickNames.append(item.id)
                case (.b, .pick): sideBPickNames.append(item.id)
                }
                showSidePicker = nil
            },
            onCancel: { showSidePicker = nil }
        )
    }

    /// Build the combined, de-duplicated pool of selectable players +
    /// draft picks for a side. Players come from the team's Sleeper
    /// roster (value > 0, not already on this side); picks are the full
    /// FantasyCalc pick set (not already on this side). Sorted by value
    /// desc so the search/filter sheet leads with the most valuable
    /// assets before the user narrows down.
    private func pickerItems(for context: TradeSidePickerContext) -> [TradePickerItem] {
        let pickedPlayers: Set<String>
        let pickedPicks: Set<String>
        switch context.side {
        case .a: pickedPlayers = Set(sideAPlayerIds); pickedPicks = Set(sideAPickNames)
        case .b: pickedPlayers = Set(sideBPlayerIds); pickedPicks = Set(sideBPickNames)
        }

        let roster = leagueStore.myLeagueRosters.first { $0.rosterId == context.rosterId }
        let players: [TradePickerItem] = (roster?.players ?? []).compactMap { pid in
            guard !pickedPlayers.contains(pid) else { return nil }
            let value = valuesStore.value(for: pid)
            guard value > 0 else { return nil }
            let player = playerStore.player(for: pid)
            return TradePickerItem(
                kind: .player,
                id: pid,
                name: player?.fullDisplayName ?? "Player #\(pid)",
                position: player?.displayPosition ?? "?",
                value: value
            )
        }

        // Filter picks to only those owned by this roster
        let ownedPickNames = picksOwned(byRosterId: context.rosterId)
        let picks: [TradePickerItem] = ownedPickNames
            .filter { !pickedPicks.contains($0) }
            .compactMap { name in
                let value = valuesStore.pickValue(for: name)
                guard value > 0 else { return nil }
                return TradePickerItem(
                    kind: .pick,
                    id: name,
                    name: name,
                    position: "PICK",
                    value: value
                )
            }

        return (players + picks).sorted { $0.value > $1.value }
    }

    /// Compute the draft pick names owned by a given roster.
    /// A roster owns:
    /// - Their original picks (where no TradedPick shows them traded away)
    /// - Picks traded TO them (TradedPick.ownerId == rosterId)
    private func picksOwned(byRosterId rosterId: Int) -> [String] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let relevantYears = [currentYear, currentYear + 1, currentYear + 2]
        let numRosters = leagueStore.myLeagueRosters.count
        let rounds = 1...5  // Dynasty rookie drafts typically 4-5 rounds

        var owned: [String] = []

        for year in relevantYears {
            let season = String(year)
            for round in rounds {
                // Check if this team's original pick (their slot) was traded
                let tradedAway = tradedPicks.first {
                    $0.season == season &&
                    $0.round == round &&
                    $0.rosterId == rosterId &&
                    $0.ownerId != rosterId
                }

                // Check if they acquired a pick from another team
                let acquired = tradedPicks.filter {
                    $0.season == season &&
                    $0.round == round &&
                    $0.ownerId == rosterId &&
                    $0.rosterId != rosterId
                }

                // If their original pick wasn't traded away, they still own it
                if tradedAway == nil {
                    let pickName = formatPickName(season: season, round: round, numRosters: numRosters)
                    owned.append(pickName)
                }

                // Add any picks they acquired
                for pick in acquired {
                    let pickName = formatPickName(season: season, round: round, numRosters: numRosters, originalRosterId: pick.rosterId)
                    owned.append(pickName)
                }
            }
        }

        return owned
    }

    /// Format pick name to match FantasyCalc naming convention.
    /// FantasyCalc uses "{year} {ordinal}" e.g. "2026 1st", "2027 2nd".
    private func formatPickName(season: String, round: Int, numRosters: Int, originalRosterId: Int? = nil) -> String {
        let roundSuffix: String
        switch round {
        case 1: roundSuffix = "1st"
        case 2: roundSuffix = "2nd"
        case 3: roundSuffix = "3rd"
        default: roundSuffix = "\(round)th"
        }
        return "\(season) \(roundSuffix)"
    }
}

// MARK: - Verdict helpers

private extension TradeEvaluation.Verdict {
    /// True once at least one side has something in it (i.e. the
    /// verdict is a real winner/fair result, not the empty placeholder).
    var isEvaluable: Bool {
        if case .empty = self { return false }
        return true
    }
}

// MARK: - Picker item

/// A single selectable asset in the trade picker — either a rostered
/// player or a FantasyCalc draft pick. `id` is the Sleeper player ID
/// for players and the pick name (e.g. "2027 Mid 1st") for picks.
private struct TradePickerItem: Identifiable, Hashable {
    enum Kind: Hashable { case player, pick }
    let kind: Kind
    let id: String
    let name: String
    /// "QB"/"RB"/"WR"/"TE"/… for players, "PICK" for picks.
    let position: String
    let value: Int
}

// MARK: - Position filter

private enum TradePositionFilter: String, CaseIterable, Identifiable {
    case all, qb, rb, wr, te, picks
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:   return "All"
        case .qb:    return "QB"
        case .rb:    return "RB"
        case .wr:    return "WR"
        case .te:    return "TE"
        case .picks: return "Picks"
        }
    }

    func matches(_ item: TradePickerItem) -> Bool {
        switch self {
        case .all:   return true
        case .picks: return item.kind == .pick
        case .qb:    return item.position == "QB"
        case .rb:    return item.position == "RB"
        case .wr:    return item.position == "WR"
        case .te:    return item.position == "TE"
        }
    }
}

// MARK: - Picker sheet

/// Searchable, position-filterable, value-sorted picker for adding a
/// player or draft pick to one side of a trade. Its own `@State` for
/// search + filter so each presentation starts fresh.
private struct TradeItemPickerSheet: View {
    let teamName: String
    let items: [TradePickerItem]
    let onSelect: (TradePickerItem) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var positionFilter: TradePositionFilter = .all

    private var filteredItems: [TradePickerItem] {
        items.filter { item in
            positionFilter.matches(item) &&
            (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            searchField
            positionFilterBar

            if filteredItems.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Matches",
                    message: "No players or picks match your search and filter. Clear them to see the full pool."
                )
                .padding(.top, XomperTheme.Spacing.xl)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: XomperTheme.Spacing.xs) {
                        ForEach(filteredItems) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                pickerRow(item: item)
                            }
                            .buttonStyle(.pressableCard)
                        }
                    }
                    .padding(.horizontal, XomperTheme.Spacing.md)
                    .padding(.bottom, XomperTheme.Spacing.md)
                }
            }
        }
        .padding(.top, XomperTheme.Spacing.md)
        .background(XomperColors.bgDark)
        .navigationTitle("Add to \(teamName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(XomperColors.championGold)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)

            TextField("Search players or picks", text: $searchText)
                .font(.body)
                .foregroundStyle(XomperColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(XomperColors.textMuted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .background(XomperColors.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private var positionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                ForEach(TradePositionFilter.allCases) { filter in
                    TradeFilterChip(
                        label: filter.label,
                        isSelected: positionFilter == filter
                    ) {
                        withAnimation(XomperTheme.defaultAnimation) {
                            positionFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
        }
    }

    private func pickerRow(item: TradePickerItem) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            if item.kind == .pick {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(XomperColors.championGold)
            }
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
            Text(item.position)
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
            Spacer()
            Text("\(item.value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }
}

// MARK: - Filter chip

private struct TradeFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? XomperColors.bgDark : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .background(isSelected ? XomperColors.championGold : XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
        }
        .buttonStyle(.pressableCard)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
