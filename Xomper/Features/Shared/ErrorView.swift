import SwiftUI

struct ErrorView: View {
    let message: String
    var retryAction: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.errorRed)
                .accessibilityHidden(true)

            Text("Something went wrong")
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, XomperTheme.Spacing.lg)

            if let retryAction {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    retryAction()
                } label: {
                    Text("Retry")
                        .font(.headline)
                        .foregroundStyle(XomperColors.deepNavy)
                        .padding(.horizontal, XomperTheme.Spacing.lg)
                        .padding(.vertical, XomperTheme.Spacing.sm)
                        .frame(minWidth: XomperTheme.minTouchTarget)
                        .frame(minHeight: XomperTheme.minTouchTarget)
                        .background(XomperColors.championGold)
                        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
                }
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(XomperTheme.defaultAnimation, value: isPressed)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressed = true }
                        .onEnded { _ in isPressed = false }
                )
            }
        }
        .padding(XomperTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
        .accessibilityHint(retryAction != nil ? "Double tap to retry" : "")
    }
}

#Preview {
    ErrorView(message: "Unable to load league data. Please check your connection.") {
        print("Retry tapped")
    }
    .preferredColorScheme(.dark)
}
