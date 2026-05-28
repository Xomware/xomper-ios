import SwiftUI

/// One CloudWatch event row in the Admin → Logs sub-screen (F5).
///
/// Layout (left → right):
/// - Level chip (capsule, ~50pt wide, color from `LogLevel.color`;
///   neutral muted color when `level` is nil)
/// - VStack(timestamp + monospaced message)
///
/// Card chrome matches the rest of the admin surface — `bgCard`
/// background, `XomperTheme.CornerRadius.md` corners, faint gold
/// stroke border, `sm` shadow. Message is monospaced + multi-line
/// + selectable so admins can copy stack traces out.
struct LogsRowView: View {
    let event: LogEvent

    var body: some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.md) {
            levelChip

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                Text(timestampLabel)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
                    .accessibilityLabel("Time \(timestampLabel)")

                Text(event.message)
                    .font(.caption.monospaced())
                    .foregroundStyle(XomperColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(
                    (event.level?.color ?? XomperColors.textMuted).opacity(0.25),
                    lineWidth: 1
                )
        )
        .xomperShadow(.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(levelAccessibilityLabel) at \(timestampLabel). \(event.message)")
    }

    // MARK: - Level chip

    @ViewBuilder
    private var levelChip: some View {
        Text(chipLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(XomperColors.bgDark)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xxs)
            .frame(minWidth: 50)
            .background(event.level?.color ?? XomperColors.textMuted)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }

    private var chipLabel: String {
        event.level?.displayName.uppercased() ?? "—"
    }

    private var levelAccessibilityLabel: String {
        event.level?.displayName ?? "Unknown level"
    }

    // MARK: - Timestamp

    /// Short relative format — "2m ago", "3h ago", "yesterday".
    /// Falls back to a compact absolute time when the event is < 1s
    /// old (RelativeDateTimeFormatter renders that as "in 0 seconds"
    /// which reads oddly).
    private var timestampLabel: String {
        let delta = Date().timeIntervalSince(event.timestamp)
        if delta < 1 {
            return event.timestamp.formatted(date: .omitted, time: .standard)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: event.timestamp, relativeTo: Date())
    }
}

#Preview {
    VStack(spacing: XomperTheme.Spacing.sm) {
        LogsRowView(event: LogEvent(
            id: "1",
            timestamp: Date().addingTimeInterval(-120),
            level: .error,
            message: "Traceback (most recent call last):\n  File \"handler.py\", line 42, in handle\n    raise ValueError(\"boom\")"
        ))
        LogsRowView(event: LogEvent(
            id: "2",
            timestamp: Date().addingTimeInterval(-3600),
            level: .warn,
            message: "Cache miss for log_group=ai-review-weekly; falling back to CloudWatch."
        ))
        LogsRowView(event: LogEvent(
            id: "3",
            timestamp: Date().addingTimeInterval(-7200),
            level: .info,
            message: "Sent test email to ***@*** for sleeper_user_id=[uid]"
        ))
        LogsRowView(event: LogEvent(
            id: "4",
            timestamp: Date().addingTimeInterval(-86400),
            level: nil,
            message: "Unstructured stdout line with no detectable level."
        ))
    }
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
