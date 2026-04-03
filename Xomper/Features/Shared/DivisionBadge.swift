import SwiftUI

struct DivisionBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(XomperColors.textSecondary)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(XomperColors.surfaceLight.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
            .accessibilityLabel("Division: \(name)")
    }
}

#Preview {
    HStack(spacing: XomperTheme.Spacing.md) {
        DivisionBadge(name: "East")
        DivisionBadge(name: "West")
        DivisionBadge(name: "Thunderdome")
    }
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
