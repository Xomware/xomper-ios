import SwiftUI

enum XomperTheme {

    // MARK: - Spacing (8pt grid)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 9999
    }

    // MARK: - Font Sizes (Dynamic Type compatible)

    enum FontSize {
        static let caption2: Font = .caption2
        static let caption: Font = .caption
        static let footnote: Font = .footnote
        static let subheadline: Font = .subheadline
        static let body: Font = .body
        static let callout: Font = .callout
        static let headline: Font = .headline
        static let title3: Font = .title3
        static let title2: Font = .title2
        static let title: Font = .title
        static let largeTitle: Font = .largeTitle
    }

    // MARK: - Minimum Touch Target

    static let minTouchTarget: CGFloat = 44

    // MARK: - Animation

    static let defaultAnimation: Animation = .easeInOut(duration: 0.2)
    static let springAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.7)

    // MARK: - Icon Sizes

    enum IconSize {
        static let sm: CGFloat = 16
        static let md: CGFloat = 24
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
    }

    // MARK: - Avatar Sizes

    enum AvatarSize {
        static let sm: CGFloat = 32
        static let md: CGFloat = 40
        static let lg: CGFloat = 56
        static let xl: CGFloat = 80
    }
}

// MARK: - Card Style Modifier

struct XomperCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .xomperShadow(.sm)
    }
}

extension View {
    func xomperCard() -> some View {
        modifier(XomperCardModifier())
    }
}
