import SwiftUI

/// Horizontal at-a-glance strip on the My Team page. Six tiles in
/// canonical order: Record, League rank, Total dynasty value,
/// Weakness, Total FPTS, Best position.
///
/// On phone-width the strip scrolls horizontally — six tiles don't
/// fit at default Dynamic Type. On regular-width (iPad) the strip
/// snaps to a non-scrolling `LazyHStack`.
///
/// Tiles that reference positional strength (Weakness, Best position)
/// are tappable and bubble back to the parent so the page can flip
/// the section picker to `.strengths`.
struct QuickHittersStrip: View {
    let data: QuickHittersData
    /// Called when the user taps Weakness or Best position. Parent
    /// uses this to switch the section picker to `.strengths`.
    var onTapStrength: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                LazyHStack(spacing: XomperTheme.Spacing.sm) { tiles }
                    .padding(.horizontal, XomperTheme.Spacing.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: XomperTheme.Spacing.sm) { tiles }
                        .padding(.horizontal, XomperTheme.Spacing.md)
                }
            }
        }
        .padding(.vertical, XomperTheme.Spacing.xs)
    }

    @ViewBuilder
    private var tiles: some View {
        recordTile
        rankTile
        valueTile
        fptsTile
        bestTile
        weakTile
    }

    // MARK: - Tiles

    private var recordTile: some View {
        tile(
            icon: "trophy.fill",
            iconColor: XomperColors.championGold,
            label: "Record",
            value: data.record,
            accent: data.streakAccent.map { ($0, data.streakLabel ?? "") }
        )
    }

    private var rankTile: some View {
        tile(
            icon: "list.number",
            iconColor: XomperColors.steelBlue,
            label: "League",
            value: data.rankDisplay,
            accent: data.rankIsTop3 ? (XomperColors.championGold, "TOP 3") : nil
        )
    }

    private var valueTile: some View {
        tile(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: XomperColors.championGold,
            label: "Dynasty",
            value: data.totalValueDisplay,
            accent: data.totalValueDelta.map { delta in
                let color: Color = delta >= 0 ? XomperColors.successGreen : XomperColors.errorRed
                let prefix = delta >= 0 ? "+" : ""
                return (color, "\(prefix)\(delta)")
            }
        )
    }

    private var fptsTile: some View {
        tile(
            icon: "flame.fill",
            iconColor: Color.orange,
            label: "FPTS",
            value: data.fptsDisplay,
            accent: nil
        )
    }

    private var bestTile: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTapStrength?()
        } label: {
            tile(
                icon: "arrow.up.right.square.fill",
                iconColor: XomperColors.successGreen,
                label: "Strongest",
                value: data.bestPosition,
                accent: nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
    }

    private var weakTile: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTapStrength?()
        } label: {
            tile(
                icon: "arrow.down.right.square.fill",
                iconColor: XomperColors.errorRed,
                label: "Weakest",
                value: data.weakestPosition,
                accent: nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tile shell

    private func tile(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        accent: (Color, String)?,
        interactive: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(iconColor)
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(XomperColors.textMuted)
                Spacer(minLength: 0)
                if interactive {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }
            }

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let (color, text) = accent {
                Text(text)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            } else {
                // Reserve the row so all tiles align vertically.
                Text(" ")
                    .font(.caption2.weight(.bold))
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.sm)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .frame(width: 116, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    XomperColors.bgCard,
                    XomperColors.bgCard.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(XomperColors.surfaceLight.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Data

/// Strongly-typed payload for `QuickHittersStrip`. Built by the
/// parent (`TeamView`) once per body invocation from existing stores
/// — keeps the strip pure-presentation and easy to preview.
struct QuickHittersData: Equatable {
    let record: String           // e.g. "8-6" or "9-4-1"
    let streakLabel: String?     // "W3" / "L2" / nil
    let streakAccent: Color?     // green / red / nil
    let rankDisplay: String      // "8th"
    let rankIsTop3: Bool         // true if leagueRank <= 3
    let totalValueDisplay: String // "42,180"
    let totalValueDelta: Int?    // delta vs league mean, nil if not computable
    let fptsDisplay: String      // "1,742.4"
    let bestPosition: String     // axis label e.g. "WR"
    let weakestPosition: String  // axis label e.g. "TE"
}
