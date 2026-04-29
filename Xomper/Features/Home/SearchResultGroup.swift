import SwiftUI

/// Renders the three possible result sections (Users / Leagues / Players) in
/// fixed order. Each section header is hidden when its bucket is empty so
/// only populated sections render.
///
/// V1 only ever populates one section (whichever matches the active
/// `SearchMode`); the grouped layout exists so a future "search-all" mode
/// can populate multiple buckets without a rendering rewrite.
struct SearchResultGroup: View {
    let results: SearchResults
    let mode: SearchMode
    let onUserTap: (SleeperUser) -> Void
    let onLeagueTap: (League) -> Void
    let onPlayerTap: (String) -> Void
    /// Resolves "owned by" info for a player in the user's home league
    /// (CLT). Returns the team name + division, or nil for free agents.
    let ownerLookup: (String) -> PlayerOwnership?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                if let user = results.user {
                    sectionHeader("Users")
                    UserResultRow(user: user, onTap: onUserTap)
                }

                if let league = results.league {
                    sectionHeader("Leagues")
                    LeagueResultRow(league: league, onTap: onLeagueTap)
                }

                if !results.players.isEmpty {
                    sectionHeader("Players")
                    ForEach(results.players) { player in
                        PlayerResultRow(
                            player: player,
                            ownership: ownerLookup(player.playerId)
                        ) {
                            onPlayerTap(player.playerId)
                        }
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.top, XomperTheme.Spacing.sm)
            .padding(.bottom, XomperTheme.Spacing.md)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(XomperColors.textMuted)
            .padding(.horizontal, XomperTheme.Spacing.xs)
            .padding(.bottom, XomperTheme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - User row

private struct UserResultRow: View {
    let user: SleeperUser
    let onTap: (SleeperUser) -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onTap(user)
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(
                    avatarID: user.avatar,
                    size: XomperTheme.AvatarSize.lg
                )

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(user.resolvedDisplayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)

                    if let username = user.username {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(XomperColors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .xomperCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View profile for \(user.resolvedDisplayName)")
        .accessibilityHint("Double tap to open profile")
    }
}

// MARK: - League row

private struct LeagueResultRow: View {
    let league: League
    let onTap: (League) -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onTap(league)
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(
                    avatarID: league.avatar,
                    size: XomperTheme.AvatarSize.lg,
                    isTeam: true
                )

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(league.displayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.sm) {
                        Label("\(league.season)", systemImage: "calendar")
                        Label("\(league.totalRosters ?? 0) teams", systemImage: "person.3")
                    }
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)

                    if league.isDynasty {
                        Text("Dynasty")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(XomperColors.deepNavy)
                            .padding(.horizontal, XomperTheme.Spacing.sm)
                            .padding(.vertical, XomperTheme.Spacing.xs)
                            .background(XomperColors.championGold)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .xomperCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(league.displayName)")
        .accessibilityHint("Double tap to open league")
    }
}

// MARK: - Player row

/// Per-player ownership in the user's home league (CLT). Resolved at
/// search-result render time from `LeagueStore.myLeagueRosters`.
struct PlayerOwnership: Sendable, Hashable {
    /// Sleeper team display name (e.g. "Nvr 4get Da CLT").
    let teamName: String
    /// `true` when this is the signed-in user's roster.
    let isMine: Bool
}

private struct PlayerResultRow: View {
    let player: Player
    let ownership: PlayerOwnership?
    let onTap: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onTap()
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                PlayerImageView(playerID: player.playerId, size: 48)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(player.fullDisplayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    Text("\(player.displayPosition) · \(player.displayTeam)")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)

                    ownershipPill
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .xomperCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view player details")
    }

    @ViewBuilder
    private var ownershipPill: some View {
        if let ownership {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: ownership.isMine ? "person.fill.checkmark" : "person.fill")
                    .font(.caption2)
                Text(ownership.isMine ? "On your team" : "Owned by \(ownership.teamName)")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(ownership.isMine ? XomperColors.bgDark : XomperColors.textPrimary)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, 3)
            .background(
                ownership.isMine
                    ? AnyShapeStyle(XomperColors.championGold)
                    : AnyShapeStyle(Color.white.opacity(0.10))
            )
            .clipShape(Capsule())
        } else {
            Text("Free agent")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
        }
    }

    private var accessibilityLabelText: String {
        let base = "\(player.fullDisplayName), \(player.displayPosition), \(player.displayTeam)"
        guard let ownership else { return "\(base), free agent" }
        if ownership.isMine { return "\(base), on your team" }
        return "\(base), owned by \(ownership.teamName)"
    }
}
