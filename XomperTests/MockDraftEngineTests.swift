import XCTest
@testable import Xomper

/// Tests for the pure-Swift `MockDraftEngine`. Engine is a pure
/// function of its inputs + RNG state so these tests don't need any
/// stores, view materialization, or networking — just synthetic
/// rookies + a fixed seed.
@MainActor
final class MockDraftEngineTests: XCTestCase {

    // MARK: - Fixtures

    /// 12-team slot order, slots 1..12 → rosters 1..12. Used for most
    /// tests so the fixture matches the league size.
    private func standardSlotOrder() -> [Int: SlotTeam] {
        var dict: [Int: SlotTeam] = [:]
        for s in 1...12 {
            dict[s] = SlotTeam(
                rosterId: s,
                userId: "u\(s)",
                teamName: "Team\(s)"
            )
        }
        return dict
    }

    /// 4 rookies per position with strictly-distinct values so BPA
    /// has a single deterministic ordering.
    private func standardRookiePool() -> [RookieCandidate] {
        var pool: [RookieCandidate] = []
        var value = 10_000.0
        for (pos, count) in [("RB", 5), ("WR", 5), ("TE", 4), ("QB", 4)] {
            for i in 0..<count {
                pool.append(RookieCandidate(
                    playerId: "\(pos.lowercased())\(i)",
                    fullName: "\(pos) Rookie \(i)",
                    position: pos,
                    nflTeam: "TM",
                    value: value
                ))
                value -= 100
            }
        }
        return pool
    }

    private func emptyTeamContext() -> TeamContext {
        TeamContext(posHPPByRoster: [:], leagueAvgByPos: [:], isFallback: true)
    }

    // MARK: - BPA

    func testBPA_isValueDescending() {
        let pool = [
            RookieCandidate(playerId: "a", fullName: "A", position: "RB", nflTeam: "T", value: 9_900),
            RookieCandidate(playerId: "b", fullName: "B", position: "WR", nflTeam: "T", value: 10_000),
            RookieCandidate(playerId: "c", fullName: "C", position: "QB", nflTeam: "T", value: 9_800),
            RookieCandidate(playerId: "d", fullName: "D", position: "TE", nflTeam: "T", value: 9_700)
        ]
        let slots = [1: SlotTeam(rosterId: 1, userId: "u1", teamName: "T1")]
        var rng = SeededRNG(seed: 1)
        let (picks, exhausted) = MockDraftEngine.run(
            rookies: pool,
            slotOrder: slots,
            rounds: 4,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .bpa },
            rng: &rng
        )
        XCTAssertFalse(exhausted)
        XCTAssertEqual(picks.map(\.playerId), ["b", "a", "c", "d"])
    }

    func testBPA_isDeterministic_acrossRuns() {
        let pool = standardRookiePool()
        let slots = standardSlotOrder()
        var r1 = SeededRNG(seed: 1)
        var r2 = SeededRNG(seed: 99) // different seed, but BPA ignores RNG
        let (a, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 5,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .bpa }, rng: &r1
        )
        let (b, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 5,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .bpa }, rng: &r2
        )
        XCTAssertEqual(a.map(\.playerId), b.map(\.playerId), "BPA must be deterministic across RNG seeds")
    }

    // MARK: - Wildcard

    func testWildcard_isDeterministicForSameSeed() {
        let pool = standardRookiePool()
        let slots = standardSlotOrder()
        var r1 = SeededRNG(seed: 42)
        var r2 = SeededRNG(seed: 42)
        let (a, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 5,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .wildcard }, rng: &r1
        )
        let (b, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 5,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .wildcard }, rng: &r2
        )
        XCTAssertEqual(a.map(\.playerId), b.map(\.playerId))
    }

    func testWildcard_variesAcrossSeeds() {
        let pool = standardRookiePool()
        let slots = standardSlotOrder()
        var r1 = SeededRNG(seed: 42)
        var r2 = SeededRNG(seed: 4242)
        let (a, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 5,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .wildcard }, rng: &r1
        )
        let (b, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 5,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .wildcard }, rng: &r2
        )
        XCTAssertNotEqual(a.map(\.playerId), b.map(\.playerId), "Wildcard with different seeds should diverge")
    }

    func testWildcard_pick1_alwaysInTop8ByValue() {
        let pool = standardRookiePool()
        let topByValue = pool.sorted { $0.value > $1.value }.prefix(MockDraftEngine.wildcardTopN)
        let topIds = Set(topByValue.map(\.playerId))

        let slots = [1: SlotTeam(rosterId: 1, userId: "u1", teamName: "T1")]
        for seed: UInt64 in [1, 2, 3, 4, 5, 100, 999, 31_337] {
            var rng = SeededRNG(seed: seed)
            let (picks, _) = MockDraftEngine.run(
                rookies: pool, slotOrder: slots, rounds: 1,
                teamContext: emptyTeamContext(),
                personality: { _, _ in .wildcard }, rng: &rng
            )
            XCTAssertEqual(picks.count, 1)
            XCTAssertTrue(topIds.contains(picks[0].playerId),
                          "Wildcard pick must be in top \(MockDraftEngine.wildcardTopN) (seed=\(seed))")
        }
    }

    // MARK: - Team Fit

    func testTeamFit_boostsWeakPositions() {
        // Roster 5 is TE-starved (HPP 100), league avg TE = 400 →
        // boost = clamp((400/100)^0.6) ≈ 2.30 clamped to 1.8.
        // Roster 5's RB room is league-average so RB boost ≈ 1.0.
        let teamContext = TeamContext(
            posHPPByRoster: [
                5: ["RB": 1_000, "WR": 1_000, "QB": 800, "TE": 100]
            ],
            leagueAvgByPos: ["RB": 1_000, "WR": 1_000, "QB": 800, "TE": 400],
            isFallback: false
        )

        // Pool: top RB at value 10_000, top TE at value 8_500. BPA
        // picks the RB. Team Fit at roster 5 should pick the TE
        // because TE value × 1.8 (clamp) = 15_300 > 10_000.
        let pool = [
            RookieCandidate(playerId: "rb_top", fullName: "RB Top", position: "RB", nflTeam: "T", value: 10_000),
            RookieCandidate(playerId: "te_top", fullName: "TE Top", position: "TE", nflTeam: "T", value: 8_500),
            RookieCandidate(playerId: "wr_top", fullName: "WR Top", position: "WR", nflTeam: "T", value: 9_500)
        ]
        let slots = [1: SlotTeam(rosterId: 5, userId: "u5", teamName: "T5")]
        var rng = SeededRNG(seed: 1)
        let (picks, _) = MockDraftEngine.run(
            rookies: pool,
            slotOrder: slots,
            rounds: 1,
            teamContext: teamContext,
            personality: { _, _ in .teamFit },
            rng: &rng
        )
        XCTAssertEqual(picks.first?.playerId, "te_top",
                       "Team Fit should pick TE when team has 4× league deficit at TE")
    }

    // MARK: - Win-Now

    func testWinNow_prefersRBoverQB_atTiedValue() {
        let pool = [
            RookieCandidate(playerId: "qb1", fullName: "QB1", position: "QB", nflTeam: "T", value: 10_000),
            RookieCandidate(playerId: "rb1", fullName: "RB1", position: "RB", nflTeam: "T", value: 10_000)
        ]
        let slots = [1: SlotTeam(rosterId: 1, userId: "u1", teamName: "T1")]
        var rng = SeededRNG(seed: 7)
        let (picks, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 1,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .winNow }, rng: &rng
        )
        XCTAssertEqual(picks.first?.playerId, "rb1",
                       "Win-Now should pick RB (1.30×) over QB (0.85×) at equal value")
    }

    // MARK: - Hype Train

    func testHypeTrain_pick1_isFromTopTwo() {
        // With values [10000, 9900, 100, 50] the top-two are
        // separated by 1%; ±1% jitter on the bottom two can't catch
        // up because their base score is dwarfed by value^1.2.
        let pool = [
            RookieCandidate(playerId: "a", fullName: "A", position: "RB", nflTeam: "T", value: 10_000),
            RookieCandidate(playerId: "b", fullName: "B", position: "WR", nflTeam: "T", value: 9_900),
            RookieCandidate(playerId: "c", fullName: "C", position: "TE", nflTeam: "T", value: 100),
            RookieCandidate(playerId: "d", fullName: "D", position: "QB", nflTeam: "T", value: 50)
        ]
        let topIds: Set<String> = ["a", "b"]
        let slots = [1: SlotTeam(rosterId: 1, userId: "u1", teamName: "T1")]
        for seed: UInt64 in [1, 2, 3, 1000, 31337] {
            var rng = SeededRNG(seed: seed)
            let (picks, _) = MockDraftEngine.run(
                rookies: pool, slotOrder: slots, rounds: 1,
                teamContext: emptyTeamContext(),
                personality: { _, _ in .hypeTrain }, rng: &rng
            )
            XCTAssertTrue(topIds.contains(picks.first?.playerId ?? ""),
                          "Hype Train pick must be from top two; seed=\(seed) picked \(picks.first?.playerId ?? "nil")")
        }
    }

    // MARK: - Pool exhaustion

    func testPoolExhaustion_doesNotCrash_andSurfaces() {
        // 30 rookies, 60-pick draft → engine stops at 30.
        var pool: [RookieCandidate] = []
        for i in 0..<30 {
            pool.append(RookieCandidate(
                playerId: "p\(i)", fullName: "P\(i)",
                position: "RB", nflTeam: "T",
                value: Double(1000 - i)
            ))
        }
        let slots = standardSlotOrder()
        var rng = SeededRNG(seed: 1)
        let (picks, exhausted) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 5,
            teamContext: emptyTeamContext(),
            personality: { _, _ in .bpa }, rng: &rng
        )
        XCTAssertEqual(picks.count, 30)
        XCTAssertTrue(exhausted)
        // No duplicates.
        XCTAssertEqual(Set(picks.map(\.playerId)).count, 30)
    }

    // MARK: - Mixed personality assignment

    func testMixed_picksRespectPerTeamPersonality() {
        // Slot 1 = Win-Now (should pick RB),
        // Slot 2 = BPA (should pick highest value not yet taken).
        let pool = [
            RookieCandidate(playerId: "qb1", fullName: "QB Top", position: "QB", nflTeam: "T", value: 10_000),
            RookieCandidate(playerId: "rb1", fullName: "RB Top", position: "RB", nflTeam: "T", value: 9_500),
            RookieCandidate(playerId: "wr1", fullName: "WR Top", position: "WR", nflTeam: "T", value: 9_400)
        ]
        let slots: [Int: SlotTeam] = [
            1: SlotTeam(rosterId: 1, userId: "u1", teamName: "T1"),
            2: SlotTeam(rosterId: 2, userId: "u2", teamName: "T2")
        ]
        let assignment: [Int: DraftPersonality] = [1: .winNow, 2: .bpa]
        var rng = SeededRNG(seed: 1)
        let (picks, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 1,
            teamContext: emptyTeamContext(),
            personality: { _, rid in assignment[rid] ?? .bpa },
            rng: &rng
        )
        XCTAssertEqual(picks.count, 2)
        // Win-Now slot1: RB (9_500 * 1.30 = 12_350) beats QB (10_000 * 0.85 = 8_500)
        XCTAssertEqual(picks[0].playerId, "rb1")
        XCTAssertEqual(picks[0].personality, .winNow)
        // BPA slot2 picks highest remaining → qb1.
        XCTAssertEqual(picks[1].playerId, "qb1")
        XCTAssertEqual(picks[1].personality, .bpa)
    }

    // MARK: - No duplicates

    func testNoRookieAppearsTwice() {
        let pool = standardRookiePool()
        let slots = standardSlotOrder()
        var rng = SeededRNG(seed: 12345)
        let (picks, _) = MockDraftEngine.run(
            rookies: pool, slotOrder: slots, rounds: 1,
            teamContext: emptyTeamContext(),
            personality: { pickNo, _ in
                DraftPersonality.allCases[pickNo % DraftPersonality.allCases.count]
            },
            rng: &rng
        )
        XCTAssertEqual(picks.count, Set(picks.map(\.playerId)).count, "No player should appear twice within a single mock")
    }

    // MARK: - needBoost helper

    func testNeedBoost_returnsOne_whenLeagueAvgIsZero() {
        let ctx = TeamContext(posHPPByRoster: [:], leagueAvgByPos: [:], isFallback: true)
        XCTAssertEqual(
            MockDraftEngine.needBoost(rosterId: 1, position: "RB", teamContext: ctx),
            1.0,
            accuracy: 0.0001
        )
    }

    func testNeedBoost_clampedToHighBound() {
        // Team has 0 at TE, league avg = 400 → ratio = 400, raw boost
        // = 400^0.6 ≈ 36, clamped to 1.8.
        let ctx = TeamContext(
            posHPPByRoster: [1: ["TE": 0]],
            leagueAvgByPos: ["TE": 400],
            isFallback: false
        )
        XCTAssertEqual(
            MockDraftEngine.needBoost(rosterId: 1, position: "TE", teamContext: ctx),
            MockDraftEngine.teamFitClampHigh,
            accuracy: 0.0001
        )
    }

    func testNeedBoost_clampedToLowBound() {
        // Team WAY above league avg → boost clamped low.
        let ctx = TeamContext(
            posHPPByRoster: [1: ["RB": 10_000]],
            leagueAvgByPos: ["RB": 1_000],
            isFallback: false
        )
        XCTAssertEqual(
            MockDraftEngine.needBoost(rosterId: 1, position: "RB", teamContext: ctx),
            MockDraftEngine.teamFitClampLow,
            accuracy: 0.0001
        )
    }
}
