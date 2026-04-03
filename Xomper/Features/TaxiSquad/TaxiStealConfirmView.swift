import SwiftUI

struct TaxiStealConfirmView: View {
    let player: TaxiSquadPlayer
    var taxiSquadStore: TaxiSquadStore
    let leagueId: String
    let leagueName: String
    let stealerName: String
    let alreadyStolen: Bool
    let isOwnPlayer: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirmation = false
    @State private var stealCompleted = false

    private var pickCost: String {
        TaxiSquadStore.stealPickText(for: player.draftRound)
    }

    private var teamColor: NFLTeamColor {
        NFLTeamColors.color(for: player.player.displayTeam)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: XomperTheme.Spacing.lg) {
                    playerHeader
                    statsGrid
                    ownershipSection
                    stealSection
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.md)
            }
            .background(XomperColors.bgDark)
            .navigationTitle(player.player.fullDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(XomperColors.championGold)
                }
            }
            .toolbarBackground(XomperColors.darkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Player Header

    private var playerHeader: some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            PlayerImageView(playerID: player.playerId, size: XomperTheme.AvatarSize.xl)
                .overlay(
                    Circle()
                        .stroke(teamColor.primary.opacity(0.6), lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                Text(player.player.fullDisplayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)

                HStack(spacing: XomperTheme.Spacing.sm) {
                    PositionBadge(position: player.player.displayPosition)

                    if let url = player.player.teamLogoURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit)
                            default:
                                EmptyView()
                            }
                        }
                        .frame(width: 20, height: 20)
                    }

                    Text(player.player.displayTeam)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)

                    if let number = player.player.number {
                        Text("#\(number)")
                            .font(.subheadline)
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }

                Text(draftText)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.md)
        .background(
            LinearGradient(
                colors: [
                    teamColor.primary.opacity(0.1),
                    XomperColors.bgCard
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .xomperShadow(.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: XomperTheme.Spacing.sm
        ) {
            statBox(label: "Age", value: player.player.age.map { "\($0)" } ?? "--")
            statBox(label: "Height", value: player.player.height ?? "--")
            statBox(label: "Weight", value: player.player.weight.map { "\($0) lbs" } ?? "--")
            statBox(label: "College", value: player.player.college ?? "--")
            statBox(label: "Experience", value: player.player.yearsExp.map { "\($0) yrs" } ?? "--")
            statBox(label: "Status", value: player.player.injuryStatus ?? "Healthy")
        }
    }

    private func statBox(label: String, value: String) -> some View {
        VStack(spacing: XomperTheme.Spacing.xs) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Ownership Section

    private var ownershipSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Ownership")
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: XomperTheme.Spacing.sm) {
                ownerRow(label: "Owner", value: player.ownerDisplayName)
                ownerRow(label: "Team", value: player.ownerTeamName)
                ownerRow(label: "Steal Cost", value: "\(pickCost) Pick")
            }
            .padding(XomperTheme.Spacing.md)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        }
    }

    private func ownerRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textMuted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(XomperColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Steal Section

    @ViewBuilder
    private var stealSection: some View {
        if stealCompleted || alreadyStolen {
            stealRequestedBanner
        } else if isOwnPlayer {
            ownPlayerBanner
        } else if showConfirmation {
            confirmationCard
        } else {
            stealButton
        }
    }

    // MARK: - Steal Button

    private var stealButton: some View {
        StealActionButton(label: "Steal for \(pickCost) Pick") {
            withAnimation(XomperTheme.defaultAnimation) {
                showConfirmation = true
            }
        }
    }

    // MARK: - Confirmation Card

    private var confirmationCard: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Text("Are you sure you want to steal **\(player.player.fullDisplayName)** for a **\(pickCost)** pick?")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textPrimary)
                .multilineTextAlignment(.center)

            if let stealError = taxiSquadStore.stealError {
                Text(stealError.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(XomperColors.errorRed)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: XomperTheme.Spacing.md) {
                cancelButton
                confirmButton
            }
        }
        .padding(XomperTheme.Spacing.lg)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .stroke(XomperColors.accentRed.opacity(0.3), lineWidth: 1)
        )
        .xomperShadow(.md)
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm steal request")
    }

    private var cancelButton: some View {
        StealActionButton(
            label: "Cancel",
            style: .secondary,
            isDisabled: taxiSquadStore.isSubmittingSteal
        ) {
            withAnimation(XomperTheme.defaultAnimation) {
                showConfirmation = false
            }
        }
    }

    private var confirmButton: some View {
        StealActionButton(
            label: taxiSquadStore.isSubmittingSteal ? "Sending..." : "Yes, Steal",
            style: .destructive,
            isDisabled: taxiSquadStore.isSubmittingSteal
        ) {
            Task {
                let success = await taxiSquadStore.submitStealRequest(
                    player: player,
                    stealerName: stealerName,
                    leagueId: leagueId,
                    leagueName: leagueName
                )
                if success {
                    withAnimation(XomperTheme.defaultAnimation) {
                        stealCompleted = true
                        showConfirmation = false
                    }
                }
            }
        }
    }

    // MARK: - Banners

    private var stealRequestedBanner: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(XomperColors.accentRed)
                .accessibilityHidden(true)

            Text("STEAL REQUESTED")
                .font(.headline)
                .foregroundStyle(XomperColors.accentRed)
        }
        .frame(maxWidth: .infinity)
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.accentRed.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .stroke(XomperColors.accentRed.opacity(0.3), lineWidth: 1)
        )
        .accessibilityLabel("Steal has been requested for this player")
    }

    private var ownPlayerBanner: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "person.fill.checkmark")
                .foregroundStyle(XomperColors.championGold)
                .accessibilityHidden(true)

            Text("This player is on your taxi squad")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.championGold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .accessibilityLabel("This player is on your taxi squad")
    }

    // MARK: - Helpers

    private var draftText: String {
        guard let round = player.draftRound, round > 0 else {
            return "Undrafted"
        }
        if let pick = player.draftPickNo, pick > 0 {
            return "Drafted Round \(round), Pick \(pick)"
        }
        return "Drafted Round \(round)"
    }
}

// MARK: - Steal Action Button

private struct StealActionButton: View {
    enum Style { case primary, secondary, destructive }

    let label: String
    var style: Style = .primary
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    private var backgroundColor: Color {
        switch style {
        case .primary: XomperColors.championGold
        case .secondary: XomperColors.surfaceLight
        case .destructive: XomperColors.accentRed
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: XomperColors.deepNavy
        case .secondary: XomperColors.textSecondary
        case .destructive: .white
        }
    }

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.headline)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(label)
    }
}

// MARK: - Preview

#Preview {
    let player = Player(
        playerId: "1234",
        firstName: "Bijan",
        lastName: "Robinson",
        fullName: "Bijan Robinson",
        position: "RB",
        team: "ATL",
        age: 22,
        college: "Texas",
        yearsExp: 2,
        status: "Active",
        injuryStatus: nil,
        number: 7,
        height: "5'10\"",
        weight: "215",
        sport: "nfl",
        active: true,
        fantasyPositions: ["RB"],
        searchFullName: nil,
        searchFirstName: nil,
        searchLastName: nil,
        depthChartPosition: nil,
        depthChartOrder: nil,
        searchRank: nil
    )

    let taxiPlayer = TaxiSquadPlayer(
        playerId: "1234",
        player: player,
        rosterId: 1,
        ownerUserId: "other-user",
        ownerDisplayName: "John Doe",
        ownerUsername: "johndoe",
        ownerTeamName: "Team JD",
        draftRound: 3,
        draftPickNo: 5
    )

    return TaxiStealConfirmView(
        player: taxiPlayer,
        taxiSquadStore: TaxiSquadStore(),
        leagueId: "123",
        leagueName: "Test League",
        stealerName: "Dominick",
        alreadyStolen: false,
        isOwnPlayer: false
    )
    .preferredColorScheme(.dark)
}
