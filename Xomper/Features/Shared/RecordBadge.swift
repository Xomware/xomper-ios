import SwiftUI

struct RecordBadge: View {
    let wins: Int
    let losses: Int
    var ties: Int = 0

    private var recordText: String {
        if ties > 0 {
            return "\(wins)-\(losses)-\(ties)"
        }
        return "\(wins)-\(losses)"
    }

    private var recordColor: Color {
        if wins > losses {
            return XomperColors.successGreen
        } else if losses > wins {
            return XomperColors.errorRed
        }
        return XomperColors.textSecondary
    }

    var body: some View {
        Text(recordText)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(recordColor)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(recordColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
            .accessibilityLabel("Record: \(wins) wins, \(losses) losses\(ties > 0 ? ", \(ties) ties" : "")")
    }
}

#Preview {
    HStack(spacing: XomperTheme.Spacing.md) {
        RecordBadge(wins: 8, losses: 3)
        RecordBadge(wins: 3, losses: 8)
        RecordBadge(wins: 5, losses: 5)
        RecordBadge(wins: 4, losses: 3, ties: 1)
    }
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
