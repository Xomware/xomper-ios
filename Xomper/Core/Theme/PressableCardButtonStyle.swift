import SwiftUI

/// Press-feedback ButtonStyle for tappable cards inside ScrollView /
/// LazyVStack. Drives a subtle scale + opacity from
/// `configuration.isPressed`, which SwiftUI's ScrollView correctly
/// defers until a tap is confirmed — so it never fights scrolls.
///
/// **Replaces the broken pattern** (`.buttonStyle(.plain)` + a
/// `simultaneousGesture(DragGesture(minimumDistance: 0))` that drove
/// `@State isPressed`). That combination caused taps to fire when the
/// user meant to scroll: the zero-distance drag swallowed the scroll
/// pan and SwiftUI couldn't disambiguate. Routing press state through
/// `ButtonStyle` is the canonical fix.
struct PressableCardButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.98
    var pressedOpacity: Double = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PressableCardButtonStyle {
    static var pressableCard: PressableCardButtonStyle { PressableCardButtonStyle() }
}
