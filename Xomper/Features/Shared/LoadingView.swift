import SwiftUI

struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            XomperLoaderPaint(size: 60)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

#Preview {
    LoadingView()
        .preferredColorScheme(.dark)
}
