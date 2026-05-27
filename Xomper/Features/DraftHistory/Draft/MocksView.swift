import SwiftUI

/// Renders the three mock-draft personalities (BPA, Team Fit,
/// Wildcard) as collapsible cards. Each card surfaces the first five
/// rounds of the 60-pick mock as a table — round / slot / team /
/// player / pos — with a "YOU" badge on the rows belonging to the
/// signed-in user.
///
/// Data flow:
/// 1. On appear, `aiReviewStore.loadMockDrafts()` pulls every
///    `type=mock` report for the league. Cached for 12 hours.
/// 2. Each report's `metadata.personality` field maps to a
///    `MockDraftPersonality`; the 60-pick `metadata.picks[]` array
///    is decoded via `AIReport.decodeMetadata(MockDraftMetadata.self)`.
/// 3. The first personality card (BPA) is expanded by default; the
///    other two start collapsed to keep the surface tight on first
///    appearance.
///
/// Backend dependency: the `"mock"` AIReportType case must be
/// recognized by the list endpoint (Xomware/xomper-back-end#62). On a
/// stack where that PR hasn't deployed yet, the fetch returns zero
/// rows and the view falls back to the empty state.
struct MocksView: View {
    var aiReviewStore: AIReviewStore
    var userStore: UserStore

    /// Tracks which personality cards are expanded. BPA expanded by
    /// default per the spec ("first expanded, rest collapsed").
    @State private var expanded: Set<MockDraftPersonality> = [.bpa]

    var body: some View {
        Group {
            if aiReviewStore.isLoadingMockDrafts && aiReviewStore.mockDrafts.isEmpty {
                LoadingView(message: "Loading mock drafts…")
            } else if let error = aiReviewStore.mockDraftsError,
                      aiReviewStore.mockDrafts.isEmpty {
                ErrorView(message: error.localizedDescription) {
                    Task { await aiReviewStore.loadMockDrafts(force: true) }
                }
            } else if aiReviewStore.mockDrafts.isEmpty {
                EmptyStateView(
                    icon: "wand.and.stars",
                    title: "No Mock Drafts Yet",
                    message: "The mock-draft engine hasn't published results for this year. Check back after the next run."
                )
            } else {
                mocksContent
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task {
            await aiReviewStore.loadMockDrafts()
        }
        .refreshable {
            await aiReviewStore.loadMockDrafts(force: true)
        }
    }

    // MARK: - Content

    private var mocksContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                ForEach(MockDraftPersonality.displayOrder, id: \.self) { personality in
                    if let report = report(for: personality) {
                        personalityCard(report: report, personality: personality)
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Personality Card

    @ViewBuilder
    private func personalityCard(report: AIReport, personality: MockDraftPersonality) -> some View {
        if let metadata = report.decodeMetadata(MockDraftMetadata.self) {
            personalityCardBody(
                report: report,
                personality: personality,
                metadata: metadata
            )
        } else {
            // Metadata couldn't be decoded — body markdown is still
            // available, but the table view depends on the structured
            // picks. Fall back to an empty card with a hint.
            personalityHeaderOnly(personality: personality, report: report)
        }
    }

    private func personalityCardBody(
        report: AIReport,
        personality: MockDraftPersonality,
        metadata: MockDraftMetadata
    ) -> some View {
        let isExpanded = expanded.contains(personality)

        return VStack(alignment: .leading, spacing: 0) {
            cardHeader(
                personality: personality,
                report: report,
                isExpanded: isExpanded
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                    Text(personality.blurb)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .padding(.top, XomperTheme.Spacing.xs)

                    Divider()
                        .overlay(XomperColors.surfaceLight)
                        .padding(.vertical, XomperTheme.Spacing.xs)

                    picksTable(picks: metadata.picks)

                    Text("Showing rounds 1–5 of \(metadata.picksCount / 12)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .padding(.top, XomperTheme.Spacing.xs)
                }
                .padding(.top, XomperTheme.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.25), lineWidth: 1)
        )
    }

    private func personalityHeaderOnly(
        personality: MockDraftPersonality,
        report: AIReport
    ) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            cardHeader(personality: personality, report: report, isExpanded: false)
            Text("Mock results couldn't be parsed.")
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    // MARK: - Header

    private func cardHeader(
        personality: MockDraftPersonality,
        report: AIReport,
        isExpanded: Bool
    ) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                if expanded.contains(personality) {
                    expanded.remove(personality)
                } else {
                    expanded.insert(personality)
                }
            }
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(personality.displayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                    Text(report.period)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
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
        .accessibilityLabel("\(personality.displayName), \(report.period)")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand to see the first five rounds")
    }

    // MARK: - Picks Table

    /// Renders rounds 1-5 as a simple table. Sleeper drafts are 12
    /// teams × 60 picks (5 rounds), so for the typical mock this is
    /// the entire roster. Filter on `round <= 5` defensively in case
    /// the engine ever runs more.
    private func picksTable(picks: [MockedPick]) -> some View {
        let myUserId = userStore.myUser?.userId
        let first5Rounds = picks
            .filter { $0.round <= 5 }
            .sorted { $0.pickNo < $1.pickNo }

        return VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            tableHeader

            ForEach(first5Rounds) { pick in
                pickRow(pick: pick, isMine: !pick.userId.isEmpty && pick.userId == myUserId)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("R")
                .frame(width: 18, alignment: .center)
            Text("Pick")
                .frame(width: 38, alignment: .center)
            Text("Team")
                .frame(width: 90, alignment: .leading)
            Text("Player")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Pos")
                .frame(width: 34, alignment: .center)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(XomperColors.textMuted)
        .textCase(.uppercase)
        .tracking(0.5)
        .padding(.vertical, XomperTheme.Spacing.xxs)
    }

    private func pickRow(pick: MockedPick, isMine: Bool) -> some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("\(pick.round)")
                .frame(width: 18, alignment: .center)
                .foregroundStyle(XomperColors.championGold)
                .font(.caption.weight(.bold))
                .monospacedDigit()

            Text("#\(pick.pickNo)")
                .frame(width: 38, alignment: .center)
                .foregroundStyle(XomperColors.textMuted)
                .font(.caption2)
                .monospacedDigit()

            Text(pick.team.isEmpty ? pick.handle : pick.team)
                .frame(width: 90, alignment: .leading)
                .font(.caption.weight(isMine ? .bold : .regular))
                .foregroundStyle(isMine ? XomperColors.championGold : XomperColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(pick.position)
                .frame(width: 34, alignment: .center)
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.bgDark)
                .padding(.vertical, 2)
                .background(positionColor(pick.position))
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
        }
        .padding(.vertical, XomperTheme.Spacing.xxs)
    }

    // MARK: - Helpers

    /// Resolves the `AIReport` for a personality by matching
    /// `metadata.personality`. Personality strings ride in the flat
    /// `metadata: [String: String]` map so we don't have to round-trip
    /// the structured decoder for the lookup.
    private func report(for personality: MockDraftPersonality) -> AIReport? {
        aiReviewStore.mockDrafts.first { report in
            let raw = report.metadata["personality"] ?? ""
            return MockDraftPersonality.from(raw) == personality
        }
    }

    private func positionColor(_ pos: String) -> Color {
        switch pos.uppercased() {
        case "QB": return Color(red: 0.95, green: 0.30, blue: 0.42)
        case "RB": return Color(red: 0.20, green: 0.80, blue: 0.50)
        case "WR": return Color(red: 0.30, green: 0.55, blue: 0.95)
        case "TE": return Color(red: 0.95, green: 0.65, blue: 0.20)
        case "K":  return Color(red: 0.65, green: 0.55, blue: 0.85)
        case "DEF", "DST": return Color(red: 0.55, green: 0.55, blue: 0.55)
        default: return XomperColors.surfaceLight
        }
    }
}

#Preview {
    MocksView(
        aiReviewStore: AIReviewStore(),
        userStore: UserStore()
    )
    .preferredColorScheme(.dark)
}
