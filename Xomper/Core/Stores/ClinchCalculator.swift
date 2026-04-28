import Foundation

/// Pure-logic namespace for World Cup clinch-status computation.
///
/// No state, no actor isolation, no async — safe to call from any context.
/// Testable in isolation via `XomperTests/ClinchCalculatorTests.swift`.
///
/// v1 limitation: uses a "max possible wins" model (wins + gamesRemaining) without
/// simulating the points-for tiebreaker. Teams tied in wins at the qualification
/// cutoff remain `.alive` even at `gamesRemaining == 0`; the tiebreaker resolves
/// at season end. This produces conservative clinch/elimination calls — a team
/// will never be falsely marked `.clinched` or `.eliminated`.
enum ClinchCalculator {

    /// Number of divisional games remaining in the current (final) World Cup season.
    ///
    /// Decrement by 1 each completed regular-season week.
    /// Final season: starts at 6, ends at 0.
    static let defaultGamesRemaining = 6

    /// Compute clinch status for each team in a single division.
    ///
    /// - Parameters:
    ///   - teams: Teams sorted wins-DESC then pointsFor-DESC by the caller.
    ///   - gamesRemaining: Remaining regular-season divisional games (defaults to `defaultGamesRemaining`).
    /// - Returns: A map of `userId → ClinchStatus`. Empty if `teams` is empty.
    static func calculate(
        teams: [WorldCupTeamRecord],
        gamesRemaining: Int = defaultGamesRemaining
    ) -> [String: ClinchStatus] {
        guard !teams.isEmpty else { return [:] }

        // 0-based index of the last qualifying seat (top 2 qualify)
        let cutoffIndex = 1
        let cutoffWins = teams.indices.contains(cutoffIndex)
            ? teams[cutoffIndex].wins
            : teams[0].wins

        var result: [String: ClinchStatus] = [:]

        for (index, team) in teams.enumerated() {
            if index <= cutoffIndex {
                // Team is currently sitting in a qualifying seat.
                // Clinched if no team below the cutoff can reach this team's wins.
                let chasers = teams.dropFirst(cutoffIndex + 1)
                let canBeCaught = chasers.contains { $0.wins + gamesRemaining >= team.wins }
                result[team.userId] = canBeCaught ? .alive : .clinched
            } else {
                // Team is currently outside the qualifying seats.
                // Eliminated if even winning every remaining game cannot reach the 2nd seed.
                let maxPossible = team.wins + gamesRemaining
                result[team.userId] = (maxPossible < cutoffWins) ? .eliminated : .alive
            }
        }

        return result
    }
}
