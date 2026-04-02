import SwiftUI

struct NFLTeamColor: Sendable {
    let primary: Color
    let secondary: Color

    init(primary: UInt, secondary: UInt) {
        self.primary = Color(hex: primary)
        self.secondary = Color(hex: secondary)
    }
}

enum NFLTeamColors {
    static let teams: [String: NFLTeamColor] = [
        "ARI": NFLTeamColor(primary: 0x97233F, secondary: 0x000000),
        "ATL": NFLTeamColor(primary: 0xA71930, secondary: 0x000000),
        "BAL": NFLTeamColor(primary: 0x241773, secondary: 0x000000),
        "BUF": NFLTeamColor(primary: 0x00338D, secondary: 0xC60C30),
        "CAR": NFLTeamColor(primary: 0x0085CA, secondary: 0x101820),
        "CHI": NFLTeamColor(primary: 0x0B162A, secondary: 0xC83803),
        "CIN": NFLTeamColor(primary: 0xFB4F14, secondary: 0x000000),
        "CLE": NFLTeamColor(primary: 0x311D00, secondary: 0xFF3C00),
        "DAL": NFLTeamColor(primary: 0x003594, secondary: 0x869397),
        "DEN": NFLTeamColor(primary: 0xFB4F14, secondary: 0x002244),
        "DET": NFLTeamColor(primary: 0x0076B6, secondary: 0xB0B7BC),
        "GB":  NFLTeamColor(primary: 0x203731, secondary: 0xFFB612),
        "HOU": NFLTeamColor(primary: 0x03202F, secondary: 0xA71930),
        "IND": NFLTeamColor(primary: 0x002C5F, secondary: 0xA2AAAD),
        "JAX": NFLTeamColor(primary: 0x006778, secondary: 0x9F792C),
        "KC":  NFLTeamColor(primary: 0xE31837, secondary: 0xFFB81C),
        "LV":  NFLTeamColor(primary: 0x000000, secondary: 0xA5ACAF),
        "LAC": NFLTeamColor(primary: 0x0080C6, secondary: 0xFFC20E),
        "LAR": NFLTeamColor(primary: 0x003594, secondary: 0xFFA300),
        "MIA": NFLTeamColor(primary: 0x008E97, secondary: 0xFC4C02),
        "MIN": NFLTeamColor(primary: 0x4F2683, secondary: 0xFFC62F),
        "NE":  NFLTeamColor(primary: 0x002244, secondary: 0xC60C30),
        "NO":  NFLTeamColor(primary: 0xD3BC8D, secondary: 0x101820),
        "NYG": NFLTeamColor(primary: 0x0B2265, secondary: 0xA71930),
        "NYJ": NFLTeamColor(primary: 0x125740, secondary: 0x000000),
        "PHI": NFLTeamColor(primary: 0x004C54, secondary: 0xA5ACAF),
        "PIT": NFLTeamColor(primary: 0x101820, secondary: 0xFFB612),
        "SF":  NFLTeamColor(primary: 0xAA0000, secondary: 0xB3995D),
        "SEA": NFLTeamColor(primary: 0x002244, secondary: 0x69BE28),
        "TB":  NFLTeamColor(primary: 0xD50A0A, secondary: 0x0A0A08),
        "TEN": NFLTeamColor(primary: 0x4B92DB, secondary: 0x002244),
        "WAS": NFLTeamColor(primary: 0x5A1414, secondary: 0xFFB612),
    ]

    static func color(for team: String) -> NFLTeamColor {
        teams[team.uppercased()] ?? NFLTeamColor(primary: 0x4A6B5C, secondary: 0x1A2E26)
    }
}
