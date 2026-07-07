import SwiftUI

// MARK: - Style extensions

extension NewsType {
    /// Accent used for the type chip + card border tint.
    var accentColor: Color {
        switch self {
        case .trade:      XomperColors.championGold
        case .waiver:     XomperColors.steelBlue
        case .freeAgent:  XomperColors.successGreen
        }
    }
}

extension LetterGrade {
    /// Grade color by tier — winner green, fair gold, loser red.
    var color: Color {
        switch tier {
        case .win:   XomperColors.successGreen
        case .fair:  XomperColors.championGold
        case .loss:  XomperColors.accentRed
        }
    }
}

// MARK: - Type chip

/// All-caps category chip, matching the AI Review row chip recipe.
struct NewsTypeChip: View {
    let type: NewsType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.systemImage)
                .font(.caption2.weight(.bold))
            Text(type.label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .foregroundStyle(XomperColors.bgDark)
        .padding(.horizontal, XomperTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(type.accentColor)
        .clipShape(Capsule())
    }
}

// MARK: - Card header

/// Shared card header: type chip + week + relative date.
struct NewsCardHeader: View {
    let item: NewsItem

    var body: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            NewsTypeChip(type: item.type)
            Text("Wk \(item.week)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
            Text(relativeNewsDate(item.createdAt))
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
                .monospacedDigit()
        }
    }
}

// MARK: - Grade badge

/// Square letter-grade badge tinted by the grade's tier.
struct GradeBadge: View {
    let grade: LetterGrade

    var body: some View {
        Text(grade.rawValue)
            .font(.headline.weight(.heavy))
            .foregroundStyle(grade.color)
            .frame(width: 44, height: 44)
            .background(grade.color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .strokeBorder(grade.color.opacity(0.5), lineWidth: 1)
            )
            .accessibilityLabel("Grade \(grade.rawValue)")
    }
}

// MARK: - Asset row

/// One player/pick line: position tag + name + dynasty value.
/// For resolved picks (draft completed), shows who the pick became.
struct AssetRow: View {
    let asset: NewsAsset

    var body: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text(asset.position)
                .font(.caption2.weight(.bold))
                .foregroundStyle(asset.isPick ? XomperColors.steelBlue : XomperColors.textMuted)
                .frame(width: 34, alignment: .leading)

            // For resolved picks, show "2024 1st → Caleb Williams"
            if asset.isResolvedPick, let playerName = asset.resolvedPlayerName {
                HStack(spacing: 4) {
                    Text(asset.name)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textPrimary)
                    Text("→")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textMuted)
                    Text(playerName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(XomperColors.championGold)
                }
                .lineLimit(1)
            } else {
                Text(asset.name)
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            if asset.value > 0 {
                Text("\(asset.value)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Helpers

/// Abbreviated relative date ("2d", "3w") for card headers.
func relativeNewsDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}
