import SwiftUI

/// Structured "team grades" panel rendered above the AI markdown on
/// `DraftRecapView`. One row per team — letter grade chip on the left,
/// manager + value-over-expected in the middle, expandable per-pick
/// breakdown with position-colored pills below.
///
/// All data is computed client-side via `DraftGradeCalculator` from
/// FantasyCalc values + the `DraftHistoryRecord` list. No backend
/// calls.
struct DraftGradesCard: View {
    let grades: [DraftGrade]
    @State private var expandedRosterId: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            header
            ForEach(orderedGrades) { grade in
                row(grade)
            }
            footnote
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    private var orderedGrades: [DraftGrade] {
        grades.sorted { $0.valueOverExpected > $1.valueOverExpected }
    }

    private var header: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("TEAM GRADES")
                .font(.caption2.weight(.bold))
                .tracking(2)
                .foregroundStyle(XomperColors.championGold)
            Spacer()
            Text("Tap a row for picks")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
        }
        .padding(.bottom, 4)
    }

    private func row(_ grade: DraftGrade) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedRosterId = expandedRosterId == grade.rosterId ? nil : grade.rosterId
                }
            }) {
                HStack(spacing: XomperTheme.Spacing.sm) {
                    letterChip(grade.letter)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(grade.teamName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(XomperColors.textPrimary)
                            .lineLimit(1)
                        Text(grade.managerName)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    voeBadge(grade.valueOverExpected)

                    Image(systemName: expandedRosterId == grade.rosterId ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if expandedRosterId == grade.rosterId {
                picksList(grade)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(XomperColors.surfaceLight.opacity(0.3))
        }
    }

    private func letterChip(_ letter: String) -> some View {
        Text(letter)
            .font(.caption.weight(.heavy))
            .foregroundStyle(XomperColors.bgDark)
            .monospacedDigit()
            .frame(width: 36, height: 28)
            .background(letterColor(letter))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// A-range → gold, B-range → green, C-range → orange, D → red.
    private func letterColor(_ letter: String) -> Color {
        if letter.hasPrefix("A") { return XomperColors.championGold }
        if letter.hasPrefix("B") { return XomperColors.successGreen }
        if letter.hasPrefix("C") { return Color.orange }
        return XomperColors.errorRed
    }

    private func voeBadge(_ voe: Int) -> some View {
        let sign = voe > 0 ? "+" : ""
        let color: Color = voe > 0 ? XomperColors.successGreen : (voe < 0 ? XomperColors.errorRed : XomperColors.textSecondary)
        return Text("\(sign)\(voe)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private func picksList(_ grade: DraftGrade) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(grade.picks) { pick in
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Text(String(format: "%d.%02d", pick.round, pick.slot))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                        .frame(width: 38, alignment: .leading)
                        .monospacedDigit()

                    positionPill(pick.position)

                    Text(pick.playerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    if !pick.nflTeam.isEmpty {
                        Text(pick.nflTeam)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }

                    Spacer()

                    voeBadge(pick.delta)
                }
            }
        }
    }

    private func positionPill(_ position: String) -> some View {
        Text(position)
            .font(.caption2.weight(.bold))
            .foregroundStyle(XomperColors.bgDark)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(positionColor(position))
            .clipShape(Capsule())
    }

    /// Same palette used by `DraftHistoryView.positionColor` so a
    /// pick chip looks the same here as in the round-by-round list.
    private func positionColor(_ position: String) -> Color {
        switch position.uppercased() {
        case "QB":  return XomperColors.errorRed
        case "RB":  return XomperColors.successGreen
        case "WR":  return Color.blue
        case "TE":  return Color.orange
        default:    return XomperColors.textMuted
        }
    }

    private var footnote: some View {
        Text("Grade = value of each pick (FantasyCalc dynasty) vs the best-available curve from this draft. + = steal, − = reach.")
            .font(.caption2)
            .foregroundStyle(XomperColors.textMuted)
            .padding(.top, 4)
    }
}
