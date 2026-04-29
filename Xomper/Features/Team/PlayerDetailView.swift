import SwiftUI

struct PlayerDetailView: View {
    let player: Player
    var playerStore: PlayerStore? = nil
    var currentSeason: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var teamColor: NFLTeamColor {
        NFLTeamColors.color(for: player.displayTeam)
    }

    /// Seasons to fetch + render in the Fantasy Production section.
    /// Falls back to the two most recent calendar years when no
    /// `currentSeason` was provided.
    private var seasonsForStats: [String] {
        if let s = currentSeason, let yr = Int(s) {
            return ["\(yr)", "\(yr - 1)"]
        }
        let year = Calendar.current.component(.year, from: Date())
        return ["\(year)", "\(year - 1)"]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                infoGrid
                    .padding(XomperTheme.Spacing.md)
            }
        }
        .background(XomperColors.bgDark)
        .overlay(alignment: .topTrailing) {
            dismissButton
        }
        .accessibilityElement(children: .contain)
        .task(id: player.playerId) {
            guard let store = playerStore else { return }
            for season in seasonsForStats {
                await store.loadSeasonStats(season)
            }
        }
    }
}

// MARK: - Header

private extension PlayerDetailView {
    var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [teamColor.primary, teamColor.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 200)
            .overlay(Color.black.opacity(0.3))

            HStack(alignment: .bottom, spacing: XomperTheme.Spacing.md) {
                playerPhoto
                playerIdentity
            }
            .padding(XomperTheme.Spacing.md)
        }
    }

    var playerPhoto: some View {
        PlayerImageView(playerID: player.playerId, size: 96)
            .overlay(
                Circle()
                    .stroke(XomperColors.championGold, lineWidth: 2)
            )
    }

    var playerIdentity: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text(player.fullDisplayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            HStack(spacing: XomperTheme.Spacing.sm) {
                PositionBadge(position: player.displayPosition)

                if let number = player.number {
                    Text("#\(number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary.opacity(0.9))
                }

                teamLabel
            }
        }
    }

    var teamLabel: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            if let url = player.teamLogoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        EmptyView()
                    }
                }
                .frame(width: 20, height: 20)
            }

            Text(player.displayTeam)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(XomperColors.textPrimary.opacity(0.9))
        }
    }
}

// MARK: - Info Grid

private extension PlayerDetailView {
    var infoGrid: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            fantasySection

            if hasPhysicalInfo {
                sectionHeader("Physical")
                LazyVGrid(columns: gridColumns, spacing: XomperTheme.Spacing.sm) {
                    if let age = player.age {
                        statCell(label: "Age", value: "\(age)")
                    }
                    if let height = player.height, !height.isEmpty {
                        statCell(label: "Height", value: formatHeight(height))
                    }
                    if let weight = player.weight, !weight.isEmpty {
                        statCell(label: "Weight", value: "\(weight) lbs")
                    }
                }
            }

            if hasBackgroundInfo {
                sectionHeader("Background")
                LazyVGrid(columns: gridColumns, spacing: XomperTheme.Spacing.sm) {
                    if let college = player.college, !college.isEmpty {
                        statCell(label: "College", value: college)
                    }
                    if let yearsExp = player.yearsExp {
                        statCell(label: "Experience", value: "\(yearsExp) yr\(yearsExp == 1 ? "" : "s")")
                    }
                }
            }

            sectionHeader("Status")
            LazyVGrid(columns: gridColumns, spacing: XomperTheme.Spacing.sm) {
                statCell(
                    label: "Status",
                    value: player.status?.capitalized ?? "Unknown",
                    valueColor: player.active == true ? XomperColors.successGreen : XomperColors.textSecondary
                )
                statCell(
                    label: "Injury",
                    value: player.injuryStatus?.capitalized ?? "Healthy",
                    valueColor: player.isInjured ? XomperColors.errorRed : XomperColors.successGreen
                )
            }
        }
    }

    var gridColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    /// "Fantasy Production" section. Renders avg PPR points per game
    /// for this season + last season when stats are available. Hidden
    /// entirely when no `playerStore` was provided OR when neither
    /// season has any data for this player.
    @ViewBuilder
    var fantasySection: some View {
        if let store = playerStore {
            let seasons = seasonsForStats
            let entries: [(season: String, stats: PlayerSeasonStats)] = seasons.compactMap { s in
                if let stats = store.stats(for: player.playerId, season: s) {
                    return (season: s, stats: stats)
                }
                return nil
            }

            if !entries.isEmpty {
                sectionHeader("Fantasy Production")
                LazyVGrid(columns: gridColumns, spacing: XomperTheme.Spacing.sm) {
                    ForEach(entries, id: \.season) { entry in
                        statCell(
                            label: "\(entry.season) PPR avg",
                            value: averageString(entry.stats.avgPointsPPR),
                            valueColor: XomperColors.championGold
                        )
                        statCell(
                            label: "\(entry.season) games",
                            value: entry.stats.gamesPlayed.map { "\($0)" } ?? "—"
                        )
                    }
                }
            } else if seasons.contains(where: { store.loadingSeasons.contains($0) }) {
                sectionHeader("Fantasy Production")
                ProgressView()
                    .tint(XomperColors.championGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, XomperTheme.Spacing.md)
            }
        }
    }

    private func averageString(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    var hasPhysicalInfo: Bool {
        player.age != nil || (player.height != nil && player.height?.isEmpty == false) ||
        (player.weight != nil && player.weight?.isEmpty == false)
    }

    var hasBackgroundInfo: Bool {
        (player.college != nil && player.college?.isEmpty == false) || player.yearsExp != nil
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(XomperColors.championGold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, XomperTheme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    func statCell(label: String, value: String, valueColor: Color = XomperColors.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.championGold)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .stroke(XomperColors.surfaceLight.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    func formatHeight(_ raw: String) -> String {
        // Sleeper stores height as total inches string (e.g. "73")
        if let totalInches = Int(raw) {
            let feet = totalInches / 12
            let inches = totalInches % 12
            return "\(feet)'\(inches)\""
        }
        return raw
    }
}

// MARK: - Dismiss Button

private extension PlayerDetailView {
    var dismissButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(minWidth: XomperTheme.minTouchTarget, minHeight: XomperTheme.minTouchTarget)
        .padding(.trailing, XomperTheme.Spacing.sm)
        .padding(.top, XomperTheme.Spacing.sm)
        .accessibilityLabel("Dismiss")
    }
}

// MARK: - Preview

#Preview {
    PlayerDetailView(
        player: Player(
            playerId: "6794",
            firstName: "Justin",
            lastName: "Jefferson",
            fullName: "Justin Jefferson",
            position: "WR",
            team: "MIN",
            age: 25,
            college: "LSU",
            yearsExp: 5,
            status: "Active",
            injuryStatus: nil,
            number: 18,
            height: "73",
            weight: "195",
            sport: "nfl",
            active: true,
            fantasyPositions: ["WR"],
            searchFullName: "justinjefferson",
            searchFirstName: "justin",
            searchLastName: "jefferson",
            depthChartPosition: nil,
            depthChartOrder: nil,
            searchRank: 10
        )
    )
    .preferredColorScheme(.dark)
}
