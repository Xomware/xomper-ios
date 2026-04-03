import Foundation

@Observable
@MainActor
final class TeamStore {

    // MARK: - State

    private(set) var myTeam: StandingsTeam?
    private(set) var currentTeam: StandingsTeam?
    private(set) var currentTeamUser: SleeperUser?

    // MARK: - Load My Team

    func loadMyTeam(from standings: [StandingsTeam], userId: String?) {
        guard let userId else { return }
        myTeam = standings.first { $0.userId == userId }
    }

    // MARK: - Set Current Team

    func setCurrentTeam(_ team: StandingsTeam, user: SleeperUser?) {
        currentTeam = team
        currentTeamUser = user
    }

    // MARK: - Reset

    func reset() {
        myTeam = nil
        currentTeam = nil
        currentTeamUser = nil
    }
}
