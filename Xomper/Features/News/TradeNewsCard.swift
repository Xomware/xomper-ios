import SwiftUI

/// Feed card for a completed trade. Social-media-inspired design with
/// engaging headlines, clear visual hierarchy, and scannable content.
struct TradeNewsCard: View {
    let item: NewsItem

    /// The winning side (if not fair) for highlight treatment.
    private var winner: NewsSide? {
        guard let grade = item.grade, !grade.isFair else { return nil }
        return item.sides.first { $0.rosterId == grade.winnerRosterId }
    }

    /// The losing side (if not fair).
    private var loser: NewsSide? {
        guard let grade = item.grade, !grade.isFair else { return nil }
        return item.sides.first { $0.rosterId != grade.winnerRosterId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top banner with grade
            headerBanner

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                // Engaging headline
                headlineSection

                // The trade itself - two columns
                tradeComparison

                // Quick verdict for scanners
                if let grade = item.grade {
                    verdictPill(grade)
                }
            }
            .padding(XomperTheme.Spacing.md)
        }
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.summary.isEmpty ? item.headline : item.summary)
    }

    // MARK: - Header Banner

    private var headerBanner: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption.weight(.bold))
                Text("TRADE")
                    .font(.caption.weight(.heavy))
                    .tracking(1)
            }
            .foregroundStyle(XomperColors.bgDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(XomperColors.championGold)

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
            // Dynamic headline based on trade outcome
            Text(engagingHeadline)
                .font(.title3.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Subtitle with teams involved
            Text("\(item.sides[safe: 0]?.teamName ?? "") & \(item.sides[safe: 1]?.teamName ?? "")")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
    }

    /// Creates an engaging headline like "Caleb Williams Headlines Blockbuster Deal"
    /// or "Fair Swap: Both Teams Get Value" instead of boring "Team A ↔ Team B"
    private var engagingHeadline: String {
        guard let grade = item.grade else { return item.headline }

        // Get the top asset from the trade
        let allAssets = item.sides.flatMap { $0.acquired }
        let topAsset = allAssets.max { $0.value < $1.value }

        if grade.isFair {
            if let top = topAsset {
                return "\(top.name) Moves in Even Swap"
            }
            return "Fair Trade: Both Sides Win"
        }

        // There's a winner
        if let winnerSide = winner, let top = topAsset {
            let pctWin = Int(grade.percentGap * 100)
            if pctWin >= 30 {
                return "\(winnerSide.teamName) Steals \(top.name)"
            } else if pctWin >= 15 {
                return "\(top.name) Headlines Lopsided Deal"
            } else {
                return "\(top.name) Swapped in Close Trade"
            }
        }

        return item.headline
    }

    // MARK: - Trade Comparison

    private var tradeComparison: some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
            if item.sides.count >= 2 {
                sideColumn(item.sides[0])

                // Swap icon divider
                VStack {
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textMuted)
                        .padding(.vertical, 8)
                    Spacer()
                }

                sideColumn(item.sides[1])
            }
        }
    }

    private func sideColumn(_ side: NewsSide) -> some View {
        let isWinner = winner?.rosterId == side.rosterId
        let isLoser = loser?.rosterId == side.rosterId

        return VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            // Team name with grade badge
            HStack(spacing: 6) {
                if let grade = item.grade {
                    Text(grade.letter(for: side.rosterId).rawValue)
                        .font(.caption.weight(.black))
                        .foregroundStyle(grade.letter(for: side.rosterId).color)
                }
                Text(side.teamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
            }

            // Received label
            Text("RECEIVED")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(XomperColors.textMuted)

            // Assets received
            if side.acquired.isEmpty {
                Text("Nothing")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(side.acquired.prefix(3)) { asset in
                        compactAssetRow(asset)
                    }
                    if side.acquired.count > 3 {
                        Text("+\(side.acquired.count - 3) more")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }
            }

            // Value total
            if side.acquiredValue > 0 {
                Text("\(side.acquiredValue) pts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isWinner ? XomperColors.successGreen : (isLoser ? XomperColors.accentRed : XomperColors.textSecondary))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .fill(isWinner ? XomperColors.successGreen.opacity(0.08) : XomperColors.surfaceLight.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(isWinner ? XomperColors.successGreen.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private func compactAssetRow(_ asset: NewsAsset) -> some View {
        HStack(spacing: 4) {
            // Position badge
            Text(asset.isPick ? "PK" : asset.position.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(XomperColors.textMuted)
                .frame(width: 18, alignment: .leading)

            // Name - show resolved player for picks, or compact pick name
            if asset.isResolvedPick, let playerName = asset.resolvedPlayerName {
                Text(playerName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(XomperColors.championGold)
                    .lineLimit(1)
            } else {
                Text(asset.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            // Value - always show for picks even if 0 (shows we tried)
            Text("\(asset.value)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(asset.value > 0 ? XomperColors.textSecondary : XomperColors.textMuted.opacity(0.5))
        }
    }

    // MARK: - Verdict Pill

    private func verdictPill(_ grade: TradeGrade) -> some View {
        HStack(spacing: 6) {
            if grade.isFair {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(XomperColors.championGold)
                Text("Fair trade")
                    .foregroundStyle(XomperColors.textSecondary)
            } else if let winner = winner {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(XomperColors.championGold)
                Text("\(winner.teamName) wins by \(grade.differential) pts")
                    .foregroundStyle(XomperColors.textSecondary)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(XomperColors.surfaceLight.opacity(0.5))
        .clipShape(Capsule())
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
