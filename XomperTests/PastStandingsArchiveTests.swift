import XCTest
@testable import Xomper

/// Coverage for the historical-standings path that powers F4's Archive →
/// Past Standings drill-down. Reuses the existing
/// `StandingsBuilder.buildStandingsFromHistory(records:)` (already covered
/// upstream by `PayoutsView`) so failures here surface directly instead of
/// only via the Payouts numbers.
@MainActor
final class PastStandingsArchiveTests: XCTestCase {

    // MARK: - Fixture

    /// Three regular-season records across three rosters:
    ///   - Roster 1 wins both its games (vs 2, vs 3)  → 2-0, 230 PF
    ///   - Roster 2 splits (loss to 1, win vs 3)      → 1-1, 200 PF
    ///   - Roster 3 loses both                        → 0-2, 165 PF
    private func makeRecords() -> [MatchupHistoryRecord] {
        let leagueId = "league-2024"
        let season = "2024"

        func record(
            week: Int,
            matchupId: Int,
            aRoster: Int, aUser: String, aPoints: Double,
            bRoster: Int, bUser: String, bPoints: Double,
            winner: Int?
        ) -> MatchupHistoryRecord {
            MatchupHistoryRecord(
                leagueId: leagueId,
                season: season,
                week: week,
                matchupId: matchupId,
                teamARosterId: aRoster,
                teamAUserId: aUser,
                teamAUsername: aUser,
                teamATeamName: "\(aUser)'s Team",
                teamAPoints: aPoints,
                teamBRosterId: bRoster,
                teamBUserId: bUser,
                teamBUsername: bUser,
                teamBTeamName: "\(bUser)'s Team",
                teamBPoints: bPoints,
                winnerRosterId: winner,
                isPlayoff: false,
                isChampionship: false,
                teamADivision: 0,
                teamBDivision: 0,
                playoffPlacement: nil
            )
        }

        return [
            // Week 1 — 1 beats 2 by 10
            record(
                week: 1, matchupId: 1,
                aRoster: 1, aUser: "alice", aPoints: 120.0,
                bRoster: 2, bUser: "bob",   bPoints: 110.0,
                winner: 1
            ),
            // Week 1 — 3 vs (bye-equivalent) — skipped; only paired games count
            // Week 2 — 1 beats 3 by big margin
            record(
                week: 2, matchupId: 2,
                aRoster: 1, aUser: "alice", aPoints: 110.0,
                bRoster: 3, bUser: "carl",  bPoints: 80.0,
                winner: 1
            ),
            // Week 3 — 2 beats 3
            record(
                week: 3, matchupId: 3,
                aRoster: 2, aUser: "bob",   aPoints: 90.0,
                bRoster: 3, bUser: "carl",  bPoints: 85.0,
                winner: 2
            ),
        ]
    }

    // MARK: - Tests

    /// Wins/losses aggregate correctly across multiple weeks; sort is
    /// wins-desc, then PF-desc — same contract Payouts depends on.
    func testBuildStandingsFromHistory_aggregatesAndSorts() {
        let records = makeRecords()
        let standings = StandingsBuilder.buildStandingsFromHistory(records: records)

        XCTAssertEqual(standings.count, 3, "expected one standings row per roster")

        // Rank 1: roster 1 (alice) — 2-0
        XCTAssertEqual(standings[0].rosterId, 1)
        XCTAssertEqual(standings[0].wins, 2)
        XCTAssertEqual(standings[0].losses, 0)
        XCTAssertEqual(standings[0].leagueRank, 1)
        XCTAssertEqual(standings[0].fpts, 230.0, accuracy: 0.001)

        // Rank 2: roster 2 (bob) — 1-1
        XCTAssertEqual(standings[1].rosterId, 2)
        XCTAssertEqual(standings[1].wins, 1)
        XCTAssertEqual(standings[1].losses, 1)
        XCTAssertEqual(standings[1].leagueRank, 2)
        XCTAssertEqual(standings[1].fpts, 200.0, accuracy: 0.001)

        // Rank 3: roster 3 (carl) — 0-2
        XCTAssertEqual(standings[2].rosterId, 3)
        XCTAssertEqual(standings[2].wins, 0)
        XCTAssertEqual(standings[2].losses, 2)
        XCTAssertEqual(standings[2].leagueRank, 3)
        XCTAssertEqual(standings[2].fpts, 165.0, accuracy: 0.001)
    }

    /// Playoff records (`isPlayoff == true`) must NOT count toward
    /// regular-season standings — that's the contract Past Standings
    /// communicates ("Final regular-season records by year").
    func testBuildStandingsFromHistory_excludesPlayoffRecords() {
        var records = makeRecords()
        // Tack on a fake playoff blowout for roster 3. Should NOT lift
        // them above roster 2 in the standings.
        records.append(
            MatchupHistoryRecord(
                leagueId: "league-2024",
                season: "2024",
                week: 15,
                matchupId: 99,
                teamARosterId: 3,
                teamAUserId: "carl",
                teamAUsername: "carl",
                teamATeamName: "carl's Team",
                teamAPoints: 200.0,
                teamBRosterId: 2,
                teamBUserId: "bob",
                teamBUsername: "bob",
                teamBTeamName: "bob's Team",
                teamBPoints: 50.0,
                winnerRosterId: 3,
                isPlayoff: true,
                isChampionship: false,
                teamADivision: 0,
                teamBDivision: 0,
                playoffPlacement: nil
            )
        )

        let standings = StandingsBuilder.buildStandingsFromHistory(records: records)
        // Roster 3 should remain last (0-2 in regular season).
        XCTAssertEqual(standings.last?.rosterId, 3)
        XCTAssertEqual(standings.last?.wins, 0)
        // PF for roster 3 should still be 165 (no playoff PF added).
        XCTAssertEqual(standings.last?.fpts ?? 0, 165.0, accuracy: 0.001)
    }

    /// Empty input must produce an empty result without crashing — the
    /// `HistoricalStandingsView` empty-state path depends on this.
    func testBuildStandingsFromHistory_emptyInput() {
        let standings = StandingsBuilder.buildStandingsFromHistory(records: [])
        XCTAssertTrue(standings.isEmpty)
    }
}
