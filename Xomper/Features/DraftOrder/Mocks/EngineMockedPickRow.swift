import SwiftUI

/// A single row inside a `MockDraftCard` showing one engine-produced
/// pick. Visually aligned with the existing draft-history row styling
/// in `DraftHistoryView` so Live / Mocks / Recap feel like siblings.
struct EngineMockedPickRow: View {
    let pick: EngineMockedPick
    /// Whether this row belongs to the signed-in user — drives the
    /// championGold highlight + YOU badge.
    let isMine: Bool
    /// Whether to show the per-pick personality chip (Mixed mode shows
    /// it; Pure mode doesn't since every row has the same
    /// personality).
    let showsPersonalityChip: Bool

    var body: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            roundNumber

            pickNumber

            teamLabel

            playerInfo

            positionChip
        }
        .padding(.vertical, XomperTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    private var roundNumber: some View {
        Text("\(pick.round)")
            .frame(width: 18, alignment: .center)
            .foregroundStyle(XomperColors.championGold)
            .font(.caption.weight(.bold))
            .monospacedDigit()
    }

    private var pickNumber: some View {
        Text("#\(pick.pickNo)")
            .frame(width: 38, alignment: .center)
            .foregroundStyle(XomperColors.textMuted)
            .font(.caption2)
            .monospacedDigit()
    }

    private var teamLabel: some View {
        Text(pick.teamName.isEmpty ? "Slot \(pick.slot)" : pick.teamName)
            .frame(width: 90, alignment: .leading)
            .font(.caption.weight(isMine ? .bold : .regular))
            .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var playerInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text(pick.playerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isMine {
                    Text("YOU")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, XomperTheme.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                }

                if showsPersonalityChip {
                    personalityChip
                }

                if pick.personality.isStochastic {
                    Image(systemName: "die.face.5")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .accessibilityLabel("Randomized pick")
                }
            }

            scoreCaption
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var personalityChip: some View {
        Text(personalityChipLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(XomperColors.bgDark)
            .padding(.horizontal, XomperTheme.Spacing.xs)
            .padding(.vertical, 1)
            .background(pick.personality.accentColor.opacity(0.85))
            .clipShape(Capsule())
    }

    private var personalityChipLabel: String {
        switch pick.personality {
        case .bpa:       "BPA"
        case .teamFit:   "FIT"
        case .wildcard:  "WLD"
        case .winNow:    "WIN"
        case .hypeTrain: "HYPE"
        }
    }

    @ViewBuilder
    private var scoreCaption: some View {
        switch pick.personality {
        case .bpa:
            // BPA score == value; suppress the caption since the
            // value chip on the right already conveys it.
            EmptyView()
        case .teamFit:
            Text(teamFitCaption)
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
                .lineLimit(1)
        case .winNow:
            Text(winNowCaption)
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
                .lineLimit(1)
        case .wildcard:
            Text("val \(Int(pick.value))")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
        case .hypeTrain:
            Text("hype → \(Int(pick.score))")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
        }
    }

    private var teamFitCaption: String {
        let value = max(pick.value, 1)
        let boost = pick.score / value
        return String(format: "fit ×%.2f → %d", boost, Int(pick.score))
    }

    private var winNowCaption: String {
        let mult = MockDraftEngine.winNowMultipliers[pick.position] ?? 1.0
        return String(format: "%@ ×%.2f → %d", pick.position, mult, Int(pick.score))
    }

    private var positionChip: some View {
        Text(pick.position)
            .frame(width: 34, alignment: .center)
            .font(.caption2.weight(.bold))
            .foregroundStyle(XomperColors.bgDark)
            .padding(.vertical, 2)
            .background(positionColor(pick.position))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
    }

    // MARK: - Helpers

    private func positionColor(_ pos: String) -> Color {
        switch pos.uppercased() {
        case "QB": return Color(red: 0.95, green: 0.30, blue: 0.42)
        case "RB": return Color(red: 0.20, green: 0.80, blue: 0.50)
        case "WR": return Color(red: 0.30, green: 0.55, blue: 0.95)
        case "TE": return Color(red: 0.95, green: 0.65, blue: 0.20)
        default:   return XomperColors.surfaceLight
        }
    }

    private var accessibilityDescription: String {
        var desc = "Pick \(pick.pickNo), round \(pick.round), \(pick.playerName), \(pick.position)"
        if !pick.nflTeam.isEmpty {
            desc += ", \(pick.nflTeam)"
        }
        desc += ", drafted by \(pick.teamName)"
        if isMine {
            desc += ". This is your pick."
        }
        return desc
    }
}
