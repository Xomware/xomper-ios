import XCTest
@testable import Xomper

/// Tests for `HighestPossibleCalculator.optimalLineupPointsByPosition`.
/// The existing `optimalLineupPoints` helper is now derived from the
/// per-position breakdown — same totals, different return shape —
/// so we also reaffirm that the total still matches expectations.
@MainActor
final class HighestPossibleCalculatorTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a `PlayerStore` seeded with synthetic players.
    /// `PlayerStore.players` is `private(set)`, so we use the test
    /// seam `setPlayersForTesting(_:)`.
    private func makeStore(_ entries: [String: String]) -> PlayerStore {
        let store = PlayerStore()
        let players = Dictionary(uniqueKeysWithValues: entries.map { id, pos in
            (id, Player(playerId: id, position: pos))
        })
        store.setPlayersForTesting(players)
        return store
    }

    // MARK: - Empty / edge cases

    func testHelper_returnsEmptyMapForEmptyInputs() {
        let store = PlayerStore()
        let result = HighestPossibleCalculator.optimalLineupPointsByPosition(
            playerPoints: [:],
            rosterPositions: [],
            playerStore: store
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testHelper_returnsEmptyMapWhenNoActiveSlots() {
        let store = PlayerStore()
        let result = HighestPossibleCalculator.optimalLineupPointsByPosition(
            playerPoints: ["p1": 10],
            rosterPositions: ["BN", "BN", "IR"],
            playerStore: store
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testHelper_skipsCandidatesWithUnknownPositions() {
        // PlayerStore returns nil for unknown ids; with no positions
        // resolvable, candidates list is empty → no buckets credited.
        let store = PlayerStore()
        let result = HighestPossibleCalculator.optimalLineupPointsByPosition(
            playerPoints: ["unknown1": 100, "unknown2": 80],
            rosterPositions: ["QB", "RB", "WR", "TE"],
            playerStore: store
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Standard slot config

    /// QB / RB / RB / WR / WR / TE / FLEX / SUPER_FLEX with a fixed
    /// per-player score grid → known per-position totals.
    ///
    /// Players + points:
    /// - qb1=30 (QB), qb2=20 (QB) — qb2 wins SUPER_FLEX
    /// - rb1=25, rb2=20, rb3=18, rb4=14
    /// - wr1=22, wr2=16, wr3=15
    /// - te1=11
    ///
    /// Optimal greedy assignment (specific slots first):
    /// - QB → qb1 (30)         → QB +30
    /// - RB → rb1 (25)         → RB +25
    /// - RB → rb2 (20)         → RB +20
    /// - WR → wr1 (22)         → WR +22
    /// - WR → wr2 (16)         → WR +16
    /// - TE → te1 (11)         → TE +11
    /// - FLEX (RB/WR/TE) → rb3 (18) wins over wr3 (15) → RB +18
    /// - SUPER_FLEX (QB/RB/WR/TE) → qb2 (20) → QB +20
    func testHelper_standardSlotConfig_breakdownCorrect() {
        let store = makeStore([
            "qb1": "QB", "qb2": "QB",
            "rb1": "RB", "rb2": "RB", "rb3": "RB", "rb4": "RB",
            "wr1": "WR", "wr2": "WR", "wr3": "WR",
            "te1": "TE"
        ])
        let pts: [String: Double] = [
            "qb1": 30, "qb2": 20,
            "rb1": 25, "rb2": 20, "rb3": 18, "rb4": 14,
            "wr1": 22, "wr2": 16, "wr3": 15,
            "te1": 11
        ]
        let slots = ["QB", "RB", "RB", "WR", "WR", "TE", "FLEX", "SUPER_FLEX", "BN", "BN"]

        let result = HighestPossibleCalculator.optimalLineupPointsByPosition(
            playerPoints: pts,
            rosterPositions: slots,
            playerStore: store
        )

        XCTAssertEqual(result["QB"] ?? 0, 50, accuracy: 0.001, "QB = qb1(30) + qb2 via SF(20)")
        XCTAssertEqual(result["RB"] ?? 0, 63, accuracy: 0.001, "RB = rb1(25) + rb2(20) + rb3 via FLEX(18)")
        XCTAssertEqual(result["WR"] ?? 0, 38, accuracy: 0.001, "WR = wr1(22) + wr2(16)")
        XCTAssertEqual(result["TE"] ?? 0, 11, accuracy: 0.001, "TE = te1(11)")
    }

    /// FLEX edge case: WR3 at 22 beats RB3 at 20 → FLEX credits WR.
    func testHelper_flexEdgeCase_creditsChosenPlayersPosition() {
        let store = makeStore([
            "qb1": "QB",
            "rb1": "RB", "rb2": "RB", "rb3": "RB",
            "wr1": "WR", "wr2": "WR", "wr3": "WR",
            "te1": "TE"
        ])
        let pts: [String: Double] = [
            "qb1": 25,
            "rb1": 20, "rb2": 15, "rb3": 20,
            "wr1": 18, "wr2": 14, "wr3": 22,
            "te1": 10
        ]
        let slots = ["QB", "RB", "RB", "WR", "WR", "TE", "FLEX", "BN"]

        // Greedy with specific-first ordering:
        // - QB → qb1 (25)
        // - RB → rb1 (20)
        // - RB → rb3 (20)
        // - WR → wr3 (22)
        // - WR → wr1 (18)
        // - TE → te1 (10)
        // - FLEX → rb2 (15) vs wr2 (14) → rb2 wins (RB +15)
        //   (wr3 already used at WR; the remaining best at flex is rb2.)
        let result = HighestPossibleCalculator.optimalLineupPointsByPosition(
            playerPoints: pts,
            rosterPositions: slots,
            playerStore: store
        )
        XCTAssertEqual(result["QB"] ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(result["RB"] ?? 0, 55, accuracy: 0.001, "rb1 + rb3 + rb2 via FLEX")
        XCTAssertEqual(result["WR"] ?? 0, 40, accuracy: 0.001, "wr3 + wr1")
        XCTAssertEqual(result["TE"] ?? 0, 10, accuracy: 0.001)
    }

    /// FLEX edge case where the highest unassigned candidate is a WR:
    /// only one WR + two RB slots already filled with great RBs leaves
    /// a strong WR available at FLEX.
    func testHelper_flexCreditsWR_whenWRwinsTheFlexSlot() {
        let store = makeStore([
            "qb1": "QB",
            "rb1": "RB", "rb2": "RB",
            "wr1": "WR", "wr2": "WR", "wr3": "WR",
            "te1": "TE"
        ])
        let pts: [String: Double] = [
            "qb1": 25,
            "rb1": 30, "rb2": 28,
            "wr1": 24, "wr2": 20, "wr3": 18,
            "te1": 10
        ]
        let slots = ["QB", "RB", "RB", "WR", "TE", "FLEX", "BN"]

        // - QB → qb1
        // - RB → rb1
        // - RB → rb2
        // - WR → wr1
        // - TE → te1
        // - FLEX → wr2 (20) vs wr3 (18) → wr2 wins (WR +20)
        let result = HighestPossibleCalculator.optimalLineupPointsByPosition(
            playerPoints: pts,
            rosterPositions: slots,
            playerStore: store
        )
        XCTAssertEqual(result["WR"] ?? 0, 44, accuracy: 0.001, "wr1(24) + wr2 via FLEX(20)")
        XCTAssertEqual(result["RB"] ?? 0, 58, accuracy: 0.001, "rb1(30) + rb2(28); rb-only slots full")
    }

    // MARK: - Total equivalence

    func testTotalEqualsSumOfPerPositionBreakdown() {
        let store = makeStore([
            "qb1": "QB", "rb1": "RB", "rb2": "RB",
            "wr1": "WR", "wr2": "WR", "te1": "TE"
        ])
        let pts: [String: Double] = [
            "qb1": 22, "rb1": 18, "rb2": 14,
            "wr1": 20, "wr2": 12, "te1": 8
        ]
        let slots = ["QB", "RB", "RB", "WR", "WR", "TE", "FLEX", "BN"]

        let total = HighestPossibleCalculator.optimalLineupPoints(
            playerPoints: pts,
            rosterPositions: slots,
            playerStore: store
        )
        let breakdown = HighestPossibleCalculator.optimalLineupPointsByPosition(
            playerPoints: pts,
            rosterPositions: slots,
            playerStore: store
        )
        XCTAssertEqual(total, breakdown.values.reduce(0, +), accuracy: 0.001)
    }
}
