import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case league
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .league: "League"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .league: "trophy.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}
