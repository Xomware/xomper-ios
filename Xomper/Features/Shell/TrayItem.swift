import SwiftUI

/// A single row in the slide-out drawer. Renders an icon + label, optionally
/// styled as the currently-selected destination (gradient bg + chevron).
///
/// Pure view — all selection / navigation side effects are owned by the
/// caller via the `action` closure.
struct TrayItem: View {
    let destination: TrayDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: destination.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                Text(destination.title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(XomperColors.textPrimary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(XomperColors.textPrimary.opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg, style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Style

    private var iconColor: Color {
        isSelected ? XomperColors.textPrimary : XomperColors.championGold
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            XomperColors.goldAccentGradient
        } else {
            Color.white.opacity(0.04)
        }
    }
}
