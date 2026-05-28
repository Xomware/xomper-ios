import SwiftUI

/// One mock-draft card — collapsible `DisclosureGroup` showing the
/// header (personality + meta) and the list of picks. Pure mode shows
/// a single personality; Mixed mode shows a per-team personality
/// summary in the header.
struct MockDraftCard: View {
    let result: MockDraftResult
    let slotOrder: [Int: SlotTeam]
    /// Sleeper user ID for the signed-in user — drives the YOU
    /// highlight on rows belonging to my team.
    let myUserId: String?
    /// Defaults expanded for the first card; the parent passes
    /// `true` only for the first card so subsequent cards start
    /// collapsed per the plan.
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                expandedBody
                    .padding(.top, XomperTheme.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: headerIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(XomperTheme.defaultAnimation, value: isExpanded)
            }
            .frame(minHeight: XomperTheme.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(titleText)
        .accessibilityHint(isExpanded ? "Collapse" : "Expand to see picks")
    }

    // MARK: - Body

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text(blurb)
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)

            if result.didExhaustPool {
                exhaustionNotice
            }

            if result.mode == .mixed {
                mixedAssignmentsSummary
            }

            Divider()
                .overlay(XomperColors.surfaceLight)
                .padding(.vertical, XomperTheme.Spacing.xs)

            tableHeader

            LazyVStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                ForEach(result.picks) { pick in
                    EngineMockedPickRow(
                        pick: pick,
                        isMine: !pick.userId.isEmpty && pick.userId == myUserId,
                        showsPersonalityChip: result.mode == .mixed
                    )
                }
            }

            footer
        }
    }

    private var exhaustionNotice: some View {
        Text("Rookie pool exhausted at pick \(result.picks.count) of \(MockDraftStore.defaultRounds * slotOrder.count). The engine stopped early so no fake players appear.")
            .font(.caption2)
            .foregroundStyle(XomperColors.accentRed)
            .padding(.vertical, XomperTheme.Spacing.xxs)
    }

    private var tableHeader: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("R").frame(width: 18, alignment: .center)
            Text("Pick").frame(width: 38, alignment: .center)
            Text("Team").frame(width: 90, alignment: .leading)
            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
            Text("Pos").frame(width: 34, alignment: .center)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(XomperColors.textMuted)
        .textCase(.uppercase)
        .tracking(0.5)
        .padding(.vertical, XomperTheme.Spacing.xxs)
    }

    private var footer: some View {
        let uniqueCount = result.uniquePlayerCount
        return Text("\(result.picks.count) picks · \(uniqueCount) unique players")
            .font(.caption2)
            .foregroundStyle(XomperColors.textMuted)
            .padding(.top, XomperTheme.Spacing.xs)
    }

    private var mixedAssignmentsSummary: some View {
        let summary = result.mixedSummary(slotOrder: slotOrder)
        return VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
            Text("Per-team personalities")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(summary, id: \.slot) { entry in
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Text("\(entry.slot).")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .frame(width: 22, alignment: .trailing)
                        .monospacedDigit()

                    Text(entry.teamName)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(entry.personality.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(entry.personality.accentColor)
                }
            }
        }
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.surfaceLight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    // MARK: - Display data

    private var accentColor: Color {
        result.purePersonality?.accentColor ?? XomperColors.championGold
    }

    private var headerIcon: String {
        result.purePersonality?.systemImage ?? "shuffle"
    }

    private var titleText: String {
        switch result.mode {
        case .pure:
            return result.purePersonality?.displayName ?? "Mock Draft"
        case .mixed:
            return "Mixed Mock #\(result.id.split(separator: "-").last ?? "")"
        }
    }

    private var subtitleText: String {
        switch result.mode {
        case .pure:
            return "Pure · every team picks this way"
        case .mixed:
            return "Mixed · per-team personalities"
        }
    }

    private var blurb: String {
        result.purePersonality?.blurb ?? "Each team is randomly assigned a personality so this mock surfaces variance across draft styles."
    }
}
