import SwiftUI

enum XomperColors {

    // MARK: - Backgrounds

    static let deepNavy = Color(hex: 0x050A08)
    static let darkNavy = Color(hex: 0x0C1612)
    static let bgDark = Color(hex: 0x030706)
    static let bgCard = Color(hex: 0x0A1610)
    static let bgCardHover = Color(hex: 0x14271E)
    static let bgInput = Color(hex: 0x14271E)

    // MARK: - Accents

    static let championGold = Color(hex: 0x00FFAB)
    static let steelBlue = Color(hex: 0x00E89D)
    static let accentRed = Color(hex: 0xFF4757)

    // MARK: - Text

    static let textPrimary = Color(hex: 0xF0F5F0)
    static let textSecondary = Color(hex: 0x8FADA0)
    static let textMuted = Color(hex: 0x4A6B5C)

    // MARK: - Semantic

    static let successGreen = Color(hex: 0x00E676)
    static let errorRed = Color(hex: 0xFF5252)
    static let surfaceLight = Color(hex: 0x1A2E26)

    // MARK: - Legacy

    static let legacyRed = Color(hex: 0xBF0A0A)
    static let legacyBlue = Color(hex: 0x1B8EDC)

    // MARK: - Gradients

    static let bgGradient = LinearGradient(
        colors: [deepNavy, darkNavy, deepNavy],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardGradient = LinearGradient(
        colors: [
            Color(hex: 0x0C1612).opacity(0.97),
            Color(hex: 0x050A08).opacity(0.97)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let goldAccentGradient = LinearGradient(
        colors: [championGold, steelBlue],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let redAccentGradient = LinearGradient(
        colors: [accentRed, Color(hex: 0xFF6B7A)],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: - Shadows

    enum Shadow {
        case sm, md, lg, xl

        var radius: CGFloat {
            switch self {
            case .sm: 2
            case .md: 4
            case .lg: 8
            case .xl: 12
            }
        }

        var y: CGFloat {
            switch self {
            case .sm: 2
            case .md: 4
            case .lg: 8
            case .xl: 12
            }
        }

        var opacity: Double {
            switch self {
            case .sm: 0.3
            case .md: 0.4
            case .lg: 0.5
            case .xl: 0.6
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - Shadow View Modifier

extension View {
    func xomperShadow(_ shadow: XomperColors.Shadow) -> some View {
        self.shadow(
            color: .black.opacity(shadow.opacity),
            radius: shadow.radius,
            x: 0,
            y: shadow.y
        )
    }
}
