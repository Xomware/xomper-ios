import SwiftUI

/// Feed card for a waiver claim or free-agent move. Social-media-inspired
/// design with clean visual hierarchy and engaging copy.
struct MoveNewsCard: View {
    let item: NewsItem

    private var side: NewsSide? { item.sides.first }

    /// Primary player being added (highest value)
    private var primaryAdd: NewsAsset? {
        side?.acquired.max { $0.value < $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top banner
            headerBanner

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                // Engaging headline
                headlineSection

                // The move details
                if let side {
                    moveDetails(side)
                }
            }
            .padding(XomperTheme.Spacing.md)
        }
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(item.type.accentColor.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.summary.isEmpty ? item.headline : item.summary)
    }

    // MARK: - Header Banner

    private var headerBanner: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: item.type == .waiver ? "clock.badge.checkmark" : "plus.circle")
                    .font(.caption.weight(.bold))
                Text(item.type == .waiver ? "WAIVER" : "FREE AGENT")
                    .font(.caption.weight(.heavy))
                    .tracking(1)
            }
            .foregroundStyle(XomperColors.bgDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(item.type.accentColor)

            Spacer()

            Text(relativeNewsDate(item.createdAt))
                .font(.caption2.weight(.medium))
                .foregroundStyle(XomperColors.textMuted)
                .padding(.trailing, XomperTheme.Spacing.md)
        }
    }

    // MARK: - Headline Section

    private var headlineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(engagingHeadline)
                .font(.headline.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let teamName = side?.teamName {
                Text(teamName)
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
            }
        }
    }

    /// Creates engaging headlines like "Patrick Mahomes Claimed!" or "Roster Shakeup: 2 In, 1 Out"
    private var engagingHeadline: String {
        guard let side else { return item.headline }

        let addCount = side.acquired.count
        let dropCount = side.relinquished.count

        // Single add
        if addCount == 1, let player = primaryAdd {
            let verb = item.type == .waiver ? "Claims" : "Signs"
            return "\(verb) \(player.name)"
        }

        // Multiple moves
        if addCount > 0 && dropCount > 0 {
            return "Roster Shakeup: \(addCount) In, \(dropCount) Out"
        }

        // Just adds
        if addCount > 1 {
            return "\(addCount) Players Added"
        }

        // Just drops
        if dropCount > 0 && addCount == 0 {
            return "\(dropCount) Player\(dropCount > 1 ? "s" : "") Released"
        }

        return item.headline
    }

    // MARK: - Move Details

    private func moveDetails(_ side: NewsSide) -> some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
            // Added column
            if !side.acquired.isEmpty {
                moveColumn(
                    label: item.type == .waiver ? "CLAIMED" : "SIGNED",
                    assets: side.acquired,
                    tint: XomperColors.successGreen,
                    faab: side.faab
                )
            }

            // Dropped column
            if !side.relinquished.isEmpty {
                moveColumn(
                    label: "DROPPED",
                    assets: side.relinquished,
                    tint: XomperColors.accentRed,
                    faab: nil
                )
            }
        }
    }

    private func moveColumn(label: String, assets: [NewsAsset], tint: Color, faab: Int?) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            // Header with optional FAAB
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(tint)

                if let faab, faab > 0 {
                    Text("$\(faab)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.championGold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(XomperColors.championGold.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            // Player list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(assets.prefix(4)) { asset in
                    playerRow(asset, tint: tint)
                }
                if assets.count > 4 {
                    Text("+\(assets.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.sm)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    private func playerRow(_ asset: NewsAsset, tint: Color) -> some View {
        HStack(spacing: 6) {
            // Position badge
            Text(asset.position.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(XomperColors.textMuted)
                .frame(width: 24)

            // Player name
            Text(asset.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)

            Spacer()

            // Value if significant
            if asset.value > 0 {
                Text("\(asset.value)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
    }
}
