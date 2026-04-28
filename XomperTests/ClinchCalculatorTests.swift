import XCTest
@testable import Xomper

final class ClinchCalculatorTests: XCTestCase {

    // MARK: - Fixture Factory

    private func makeTeam(
        id: String,
        wins: Int,
        losses: Int = 0,
        pointsFor: Double? = nil,
        division: Int = 1,
        divisionName: String = "Test"
    ) -> WorldCupTeamRecord {
        WorldCupTeamRecord(
            userId: id,
            username: id,
            teamName: id,
            division: division,
            divisionName: divisionName,
            wins: wins,
            losses: losses,
            ties: 0,
            pointsFor: pointsFor ?? Double(wins) * 100,
            pointsAgainst: 0,
            clinchStatus: .alive,
            seasonBreakdown: []
        )
    }

    // MARK: - Test 1: Top two both alive when chasers can catch up

    func testTopTwoBothAlive_whenChasersCanCatchUp() {
        // 4-team division: 8-2, 7-3, 6-4, 5-5; gamesRemaining = 6
        // rank-3: 6+6=12 >= rank-1's 8 → can catch → rank-1 alive
        // rank-4: 5+6=11 >= rank-2's 7 → can catch → rank-2 alive
        // rank-3: 6+6=12 >= cutoff 7 → not eliminated → alive
        // rank-4: 5+6=11 >= cutoff 7 → not eliminated → alive
        let teams = [
            makeTeam(id: "u1", wins: 8, losses: 2),
            makeTeam(id: "u2", wins: 7, losses: 3),
            makeTeam(id: "u3", wins: 6, losses: 4),
            makeTeam(id: "u4", wins: 5, losses: 5)
        ]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 6)
        XCTAssertEqual(result["u1"], .alive)
        XCTAssertEqual(result["u2"], .alive)
        XCTAssertEqual(result["u3"], .alive)
        XCTAssertEqual(result["u4"], .alive)
    }

    // MARK: - Test 2: First seed clinched, second alive, third alive, fourth eliminated

    func testFirstSeedClinched_secondAlive_thirdAlive_fourthEliminated() {
        // 4-team division: 12-0, 8-4, 6-6, 3-9; gamesRemaining = 2
        // rank-1 (12 wins): chasers max = max(6,3)+2 = 8 < 12 → clinched
        // rank-2 (8 wins): chasers max = max(6,3)+2 = 8 >= 8 → alive (can be caught)
        // rank-3 (6 wins): max = 6+2=8 = cutoff 8 → NOT strictly less → alive
        // rank-4 (3 wins): max = 3+2=5 < 8 → eliminated
        let teams = [
            makeTeam(id: "u1", wins: 12, losses: 0),
            makeTeam(id: "u2", wins: 8,  losses: 4),
            makeTeam(id: "u3", wins: 6,  losses: 6),
            makeTeam(id: "u4", wins: 3,  losses: 9)
        ]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 2)
        XCTAssertEqual(result["u1"], .clinched)
        XCTAssertEqual(result["u2"], .alive)
        XCTAssertEqual(result["u3"], .alive)
        XCTAssertEqual(result["u4"], .eliminated)
    }

    // MARK: - Test 3: Both top seeds clinched, bottom two eliminated

    func testSecondSeedClinched_whenAllChasersFarBack() {
        // 4-team division: 12-0, 10-2, 3-9, 2-10; gamesRemaining = 6
        // rank-1 (12): chasers max = 3+6=9 < 12 → clinched
        // rank-2 (10): chasers max = 3+6=9 < 10 → clinched
        // rank-3 (3): max = 3+6=9 < cutoff 10 → eliminated
        // rank-4 (2): max = 2+6=8 < cutoff 10 → eliminated
        let teams = [
            makeTeam(id: "u1", wins: 12, losses: 0),
            makeTeam(id: "u2", wins: 10, losses: 2),
            makeTeam(id: "u3", wins: 3,  losses: 9),
            makeTeam(id: "u4", wins: 2,  losses: 10)
        ]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 6)
        XCTAssertEqual(result["u1"], .clinched)
        XCTAssertEqual(result["u2"], .clinched)
        XCTAssertEqual(result["u3"], .eliminated)
        XCTAssertEqual(result["u4"], .eliminated)
    }

    // MARK: - Test 4: Bottom two eliminated in a 6-team division

    func testFifthEliminated_inSixTeamDivision() {
        // 6-team: 9-1, 8-2, 7-3, 6-4, 1-9, 0-10; gamesRemaining = 2
        // cutoff = rank-2's 8 wins
        // rank-1 (9): chasers = ranks 3-6; rank-3 max = 7+2=9 >= 9 → can catch → alive
        // rank-2 (8): chasers = ranks 3-6; rank-3 max = 9 >= 8 → alive
        // rank-3 (7): outside cutoff; max = 7+2=9 >= 8 → alive
        // rank-4 (6): outside cutoff; max = 6+2=8 >= 8 → alive
        // rank-5 (1): max = 1+2=3 < 8 → eliminated
        // rank-6 (0): max = 0+2=2 < 8 → eliminated
        let teams = [
            makeTeam(id: "u1", wins: 9, losses: 1),
            makeTeam(id: "u2", wins: 8, losses: 2),
            makeTeam(id: "u3", wins: 7, losses: 3),
            makeTeam(id: "u4", wins: 6, losses: 4),
            makeTeam(id: "u5", wins: 1, losses: 9),
            makeTeam(id: "u6", wins: 0, losses: 10)
        ]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 2)
        XCTAssertEqual(result["u1"], .alive)
        XCTAssertEqual(result["u2"], .alive)
        XCTAssertEqual(result["u3"], .alive)
        XCTAssertEqual(result["u4"], .alive)
        XCTAssertEqual(result["u5"], .eliminated)
        XCTAssertEqual(result["u6"], .eliminated)
    }

    // MARK: - Test 5: All tied, everyone alive

    func testTiesAtCutoff_allAlive() {
        // 4-team all 7-3; gamesRemaining = 1
        // rank-1: chasers max = 7+1=8 >= 7 → alive
        // rank-2: chasers max = 8 >= 7 → alive
        // rank-3: max = 7+1=8 >= cutoff 7 → alive
        // rank-4: max = 8 >= 7 → alive
        let teams = [
            makeTeam(id: "u1", wins: 7, losses: 3, pointsFor: 800),
            makeTeam(id: "u2", wins: 7, losses: 3, pointsFor: 700),
            makeTeam(id: "u3", wins: 7, losses: 3, pointsFor: 600),
            makeTeam(id: "u4", wins: 7, losses: 3, pointsFor: 500)
        ]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 1)
        XCTAssertEqual(result["u1"], .alive)
        XCTAssertEqual(result["u2"], .alive)
        XCTAssertEqual(result["u3"], .alive)
        XCTAssertEqual(result["u4"], .alive)
    }

    // MARK: - Test 6: Zero games played, everyone alive

    func testZeroGamesPlayed_everyoneAlive() {
        // All 0-0, gamesRemaining = 6 → everyone can go 6-0 and tie for top-2
        let teams = [
            makeTeam(id: "u1", wins: 0),
            makeTeam(id: "u2", wins: 0),
            makeTeam(id: "u3", wins: 0),
            makeTeam(id: "u4", wins: 0)
        ]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 6)
        XCTAssertEqual(result["u1"], .alive)
        XCTAssertEqual(result["u2"], .alive)
        XCTAssertEqual(result["u3"], .alive)
        XCTAssertEqual(result["u4"], .alive)
    }

    // MARK: - Test 7: Season over (0 games remaining)

    func testSeasonOver_zeroGamesRemaining() {
        // 4-team: 8-2, 7-3, 6-4, 5-5; gamesRemaining = 0
        // rank-1 (8): chasers max = max(6,5)+0=6 < 8 → clinched
        // rank-2 (7): chasers max = 6+0=6 < 7 → clinched
        // rank-3 (6): max = 6+0=6 < cutoff 7 → eliminated
        // rank-4 (5): max = 5+0=5 < 7 → eliminated
        let teams = [
            makeTeam(id: "u1", wins: 8, losses: 2),
            makeTeam(id: "u2", wins: 7, losses: 3),
            makeTeam(id: "u3", wins: 6, losses: 4),
            makeTeam(id: "u4", wins: 5, losses: 5)
        ]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 0)
        XCTAssertEqual(result["u1"], .clinched)
        XCTAssertEqual(result["u2"], .clinched)
        XCTAssertEqual(result["u3"], .eliminated)
        XCTAssertEqual(result["u4"], .eliminated)
    }

    // MARK: - Test 8: Empty division returns empty map

    func testEmptyDivision_returnsEmptyMap() {
        let result = ClinchCalculator.calculate(teams: [], gamesRemaining: 6)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Test 9: Single team division is clinched

    func testSingleTeamDivision_clinched() {
        let teams = [makeTeam(id: "u1", wins: 0)]
        let result = ClinchCalculator.calculate(teams: teams, gamesRemaining: 6)
        XCTAssertEqual(result["u1"], .clinched)
    }
}
