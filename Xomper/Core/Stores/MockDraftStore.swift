import Foundation

/// Orchestrates the client-side mock-draft engine. Owns the rookie
/// pool derivation, the `TeamContext` snapshot, and the cached Pure +
/// Mixed results for the current session.
///
/// View flow:
/// 1. `MocksView` calls `ensureLoaded(...)` on appear (idempotent).
/// 2. Store builds `TeamContext`, derives the rookie pool, and runs
///    the engine once per personality (Pure) and three times with
///    random per-team assignments (Mixed). Both modes pre-baked so
///    toggling between them is instant.
/// 3. `reshuffle()` bumps `currentSeed` and regenerates all stochastic
///    results. Deterministic mocks (BPA / Team Fit / Win-Now) are
///    untouched — same seed, same input, same output.
@Observable
@MainActor
final class MockDraftStore {

    // MARK: - State

    enum Status: Sendable, Equatable {
        case idle
        case pending
        case ready
        case noUpcomingDraft
        case noRookiePool
        case error(String)
    }

    private(set) var status: Status = .idle

    /// Personality → Pure mock result. One entry per personality the
    /// engine knows about (5 entries when fully populated).
    private(set) var pureMocks: [DraftPersonality: MockDraftResult] = [:]

    /// 3 Mixed mocks. Each has a distinct seed and a random per-team
    /// personality assignment.
    private(set) var mixedMocks: [MockDraftResult] = []

    /// Resolved slot order from `historyStore.upcomingDraft.draft_order`.
    /// `slot → SlotTeam` so the view can render the team next to each
    /// pick.
    private(set) var slotOrder: [Int: SlotTeam] = [:]

    /// The rookie pool used to generate the current results. Surfaced
    /// for tests + a debug footer in dev builds.
    private(set) var rookiePool: [RookieCandidate] = []

    /// Whether the pool was widened from `yearsExp == 0` to
    /// `yearsExp ∈ {0, 1}` because the strict intersection was too
    /// small. View surfaces a header warning when true.
    private(set) var didFallbackPool: Bool = false

    /// `TeamContext.isFallback` for the current run — surfaced so the
    /// view can warn when Team Fit degrades to BPA.
    private(set) var didFallbackTeamContext: Bool = false

    /// Active viewing mode. Defaults to Pure on first appear per the
    /// plan.
    private(set) var mode: MockDraftResult.Mode = .pure

    /// Current RNG seed. Bumped by `reshuffle()` so stochastic mocks
    /// re-roll while deterministic mocks stay stable.
    private(set) var currentSeed: UInt64 = 0xC0FFEE_5EED

    // MARK: - Config (defaults match the plan)

    /// Rookie draft rounds. 5 rounds × 12 teams = 60 picks in the
    /// happy path.
    static let defaultRounds: Int = 5

    /// Minimum pool size before triggering the fallback widen to
    /// `yearsExp ∈ {0, 1}`.
    static let minPoolSize: Int = 60

    /// Cache identity: bumps when the underlying draft / values
    /// snapshots change so `ensureLoaded` knows to regenerate.
    private var lastBuildKey: String?

    // MARK: - Public API

    /// Idempotent loader. Builds `TeamContext`, derives the rookie
    /// pool, and generates Pure + Mixed mocks for the current
    /// session. No-op when the relevant snapshots haven't changed.
    func ensureLoaded(
        leagueStore: LeagueStore,
        historyStore: HistoryStore,
        playerStore: PlayerStore,
        playerValuesStore: PlayerValuesStore,
        playerPointsStore: PlayerPointsStore,
        regularSeasonLastWeek: Int
    ) {
        // Gate on the dependencies the engine needs.
        guard let upcomingDraft = historyStore.upcomingDraft else {
            status = .noUpcomingDraft
            return
        }
        guard playerValuesStore.hasValues else {
            status = .pending
            return
        }
        guard !playerStore.players.isEmpty else {
            status = .pending
            return
        }

        // Snake-draft warning per PLAN.md step 18. v1 ships linear-only;
        // we render the mocks anyway under linear assumptions.
        if let type = upcomingDraft.type?.lowercased(),
           type == "snake" {
            // Just log — the view surfaces a banner. (No print(); use
            // os_log later if needed.)
            _ = type
        }

        let buildKey = makeBuildKey(
            draftId: upcomingDraft.draftId,
            valuesLoadedAt: playerValuesStore.lastLoadedAt,
            seed: currentSeed
        )
        if buildKey == lastBuildKey { return }

        // Resolve slot order from `draft_order` + upcoming users +
        // rosters.
        let slots = resolveSlotOrder(
            draft: upcomingDraft,
            historyStore: historyStore
        )
        guard !slots.isEmpty else {
            status = .noUpcomingDraft
            return
        }
        slotOrder = slots

        // Build the rookie pool.
        let (pool, didFallback) = buildRookiePool(
            playerStore: playerStore,
            playerValuesStore: playerValuesStore
        )
        guard !pool.isEmpty else {
            status = .noRookiePool
            return
        }
        rookiePool = pool
        didFallbackPool = didFallback

        // Per-roster per-position HPP snapshot.
        let rosterIds = Array(Set(slots.values.map { $0.rosterId })).sorted()
        let context = TeamContext.build(
            rosterIds: rosterIds,
            leagueStore: leagueStore,
            playerStore: playerStore,
            playerPointsStore: playerPointsStore,
            regularSeasonLastWeek: regularSeasonLastWeek
        )
        didFallbackTeamContext = context.isFallback

        // Generate Pure + Mixed.
        regenerateAll(teamContext: context)

        lastBuildKey = buildKey
        status = .ready
    }

    /// Bumps the seed and regenerates stochastic mocks. BPA, Team Fit,
    /// and Win-Now are deterministic so their entries don't change —
    /// but we re-run them anyway for symmetry (cheap; 60 picks × 458
    /// rookies × 5 personalities is sub-millisecond).
    func reshuffle(
        leagueStore: LeagueStore,
        historyStore: HistoryStore,
        playerStore: PlayerStore,
        playerValuesStore: PlayerValuesStore,
        playerPointsStore: PlayerPointsStore,
        regularSeasonLastWeek: Int
    ) {
        currentSeed = currentSeed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678_9ABC_DEF1
        lastBuildKey = nil
        ensureLoaded(
            leagueStore: leagueStore,
            historyStore: historyStore,
            playerStore: playerStore,
            playerValuesStore: playerValuesStore,
            playerPointsStore: playerPointsStore,
            regularSeasonLastWeek: regularSeasonLastWeek
        )
    }

    func setMode(_ newMode: MockDraftResult.Mode) {
        mode = newMode
    }

    // MARK: - Generation

    private func regenerateAll(teamContext: TeamContext) {
        var newPure: [DraftPersonality: MockDraftResult] = [:]

        // Pure: one mock per personality. Each personality draws from
        // its own RNG slice so reshuffle's seed change propagates to
        // both stochastic personalities, not just whichever was
        // generated first.
        for (i, p) in DraftPersonality.displayOrder.enumerated() {
            var rng = SeededRNG(seed: currentSeed &+ UInt64(i))
            let (picks, didExhaust) = MockDraftEngine.run(
                rookies: rookiePool,
                slotOrder: slotOrder,
                rounds: Self.defaultRounds,
                teamContext: teamContext,
                personality: { _, _ in p },
                rng: &rng
            )
            newPure[p] = MockDraftResult(
                id: "pure-\(p.rawValue)",
                mode: .pure,
                purePersonality: p,
                picks: picks,
                personalityByRosterId: nil,
                seed: currentSeed &+ UInt64(i),
                didExhaustPool: didExhaust
            )
        }
        pureMocks = newPure

        // Mixed: 3 mocks, each with random per-team personality
        // assignments. Use the seed to drive the assignment too so
        // reshuffle changes the team→personality map AND the
        // stochastic picks.
        let rosterIds = Array(Set(slotOrder.values.map { $0.rosterId })).sorted()
        var newMixed: [MockDraftResult] = []
        for i in 0..<3 {
            let mockSeed = currentSeed &+ UInt64(100 + i)
            var assignmentRNG = SeededRNG(seed: mockSeed)
            var assignment: [Int: DraftPersonality] = [:]
            for rid in rosterIds {
                let idx = assignmentRNG.nextInt(in: 0..<DraftPersonality.allCases.count)
                assignment[rid] = DraftPersonality.allCases[idx]
            }

            var runRNG = SeededRNG(seed: mockSeed &+ 1)
            let (picks, didExhaust) = MockDraftEngine.run(
                rookies: rookiePool,
                slotOrder: slotOrder,
                rounds: Self.defaultRounds,
                teamContext: teamContext,
                personality: { _, rosterId in
                    assignment[rosterId] ?? .bpa
                },
                rng: &runRNG
            )
            newMixed.append(
                MockDraftResult(
                    id: "mixed-\(mockSeed)",
                    mode: .mixed,
                    purePersonality: nil,
                    picks: picks,
                    personalityByRosterId: assignment,
                    seed: mockSeed,
                    didExhaustPool: didExhaust
                )
            )
        }
        mixedMocks = newMixed
    }

    // MARK: - Slot order

    /// Resolves `slot → SlotTeam` from the upcoming-draft snapshot.
    /// `draft.draftOrder` is `[user_id: slot]`; cross-reference with
    /// `upcomingUsers` for display names and `upcomingRosters` for
    /// roster IDs.
    private func resolveSlotOrder(
        draft: Draft,
        historyStore: HistoryStore
    ) -> [Int: SlotTeam] {
        guard let order = draft.draftOrder, !order.isEmpty else { return [:] }
        var bySlot: [Int: SlotTeam] = [:]
        for (userId, slot) in order {
            let user = historyStore.upcomingUsers.first { ($0.userId ?? "") == userId }
            let roster = historyStore.upcomingRosters.first { $0.ownerId == userId }
            guard let rosterId = roster?.rosterId else { continue }
            let teamName = user?.teamName ?? user?.resolvedDisplayName ?? "Slot \(slot)"
            bySlot[slot] = SlotTeam(
                rosterId: rosterId,
                userId: userId,
                teamName: teamName
            )
        }
        return bySlot
    }

    // MARK: - Rookie pool

    /// Builds the rookie pool. Strict intersection of
    /// `Player.yearsExp == 0` ∩ FantasyCalc dynasty values ∩ skill
    /// positions (QB / RB / WR / TE). Widens to
    /// `yearsExp ∈ {0, 1}` if the strict intersection is under
    /// `minPoolSize` players.
    func buildRookiePool(
        playerStore: PlayerStore,
        playerValuesStore: PlayerValuesStore
    ) -> (pool: [RookieCandidate], didFallback: Bool) {
        let skillPositions: Set<String> = ["QB", "RB", "WR", "TE"]

        func candidate(for playerId: String, player: Player) -> RookieCandidate? {
            let value = playerValuesStore.value(for: playerId)
            guard value > 0 else { return nil }
            let position = player.displayPosition
            guard skillPositions.contains(position.uppercased()) else { return nil }
            return RookieCandidate(
                playerId: playerId,
                fullName: player.fullDisplayName,
                position: position,
                nflTeam: player.displayTeam,
                value: Double(value)
            )
        }

        // Strict pool.
        var strict: [RookieCandidate] = []
        for (pid, player) in playerStore.players where player.yearsExp == 0 {
            if let c = candidate(for: pid, player: player) {
                strict.append(c)
            }
        }
        if strict.count >= Self.minPoolSize {
            return (strict.sorted { $0.value > $1.value }, false)
        }

        // Fallback: widen to yearsExp ∈ {0, 1}.
        var widened: [RookieCandidate] = strict
        var seen = Set(strict.map(\.playerId))
        for (pid, player) in playerStore.players
        where (player.yearsExp == 1) && !seen.contains(pid) {
            if let c = candidate(for: pid, player: player) {
                widened.append(c)
                seen.insert(pid)
            }
        }
        return (widened.sorted { $0.value > $1.value }, !widened.isEmpty && widened.count > strict.count)
    }

    // MARK: - Cache key

    private func makeBuildKey(
        draftId: String,
        valuesLoadedAt: Date?,
        seed: UInt64
    ) -> String {
        let stamp = valuesLoadedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "nil"
        return "\(draftId)|\(stamp)|\(seed)"
    }
}
