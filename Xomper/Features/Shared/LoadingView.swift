import SwiftUI

struct LoadingView: View {
    var message: String = "Loading..."

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    XomperColors.goldAccentGradient,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: 1.0).repeatForever(autoreverses: false),
                    value: isAnimating
                )

            Text(message)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark)
        .onAppear {
            isAnimating = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

#Preview {
    LoadingView()
        .preferredColorScheme(.dark)
}
