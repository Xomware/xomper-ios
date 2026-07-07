import SwiftUI

/// Feed card for a waiver claim or free-agent move (a single team adding
/// and/or dropping players). No grade — moves aren't zero-sum trades —
/// but FAAB spend is surfaced when present.
struct MoveNewsCard: View {
    let item: NewsItem

    private var side: NewsSide? { item.sides.first }

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            NewsCardHeader(item: item)

            Text(item.headline)
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)

            if let side {
                if !side.acquired.isEmpty {
                    moveGroup(
                        label: item.type == .waiver ? "Claimed" : "Added",
                        assets: side.acquired,
                        tint: XomperColors.successGreen,
                        faab: side.faab
                    )
                }
                if !side.relinquished.isEmpty {
                    moveGroup(
                        label: "Dropped",
                        assets: side.relinquished,
                        tint: XomperColors.accentRed,
                        faab: nil
                    )
                }
            }

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(item.type.accentColor.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.summary.isEmpty ? item.headline : item.summary)
    }

    private func moveGroup(label: String, assets: [NewsAsset], tint: Color, faab: Int?) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(tint)
                if let faab, faab > 0 {
                    Text("$\(faab) FAAB")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
            ForEach(assets) { AssetRow(asset: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.surfaceLight.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }
}
