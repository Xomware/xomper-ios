import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case league
    case myTeam
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .league: "League"
        case .myTeam: "My Team"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .league: "trophy.fill"
        case .myTeam: "person.3.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}
