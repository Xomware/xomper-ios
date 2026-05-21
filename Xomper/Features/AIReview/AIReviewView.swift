import SwiftUI

/// AI Review archive. Newest-first list of every report the backend
/// has generated. Tapping a row pushes `AIReviewDetailView`. Pull-
/// to-refresh forces a re-fetch; the last row triggers
/// `store.loadMore()` for infinite scroll.
///
/// Until the backend's `/ai-reports/list` endpoint is live the call
/// errors out — the view renders the error inline. Once the route
/// returns an empty array the empty state appears instead.
struct AIReviewView: View {
    let store: AIReviewStore
    let router: AppRouter

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                if store.isLoading && store.archive.isEmpty {
                    LoadingView(message: "Loading reports…")
                        .padding(.top, XomperTheme.Spacing.xl)
                } else if let error = store.error, store.archive.isEmpty {
                    ErrorView(message: error.localizedDescription) {
                        Task { await store.loadArchive(force: true) }
                    }
                    .padding(.top, XomperTheme.Spacing.lg)
                } else if store.archive.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: "No reports yet",
                        message: "First one lands after the next draft."
                    )
                    .padding(.top, XomperTheme.Spacing.xl)
                } else {
                    ForEach(Array(store.archive.enumerated()), id: \.element.id) { idx, report in
                        AIReportCardRow(report: report) {
                            router.navigate(to: .aiReportDetail(reportId: report.id))
                        }
                        .padding(.horizontal, XomperTheme.Spacing.md)
                        .onAppear {
                            // Infinite scroll: when the last visible
                            // row mounts, request the next page.
                            // No-op when the cursor is nil.
                            if idx == store.archive.count - 1 {
                                Task { await store.loadMore() }
                            }
                        }
                    }

                    if store.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(XomperColors.championGold)
                            Spacer()
                        }
                        .padding(.vertical, XomperTheme.Spacing.md)
                    }
                }
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task {
            await store.loadArchive()
        }
        .refreshable {
            await store.refresh()
        }
    }
}

// MARK: - Row

/// Compact archive row — type chip, period, snippet, relative date.
/// Tappable card with the standard pressable feedback.
private struct AIReportCardRow: View {
    let report: AIReport
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    typeChip
                    Text(report.period)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textSecondary)
                    Spacer()
                    Text(relativeDate(report.createdAt))
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                }

                if !report.previewSnippet.isEmpty {
                    Text(report.previewSnippet)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
            .padding(XomperTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(report.reportType.accentColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(report.reportType.displayName) report, \(report.period)")
        .accessibilityHint("Double tap to read full report")
    }

    private var typeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: report.reportType.systemImage)
                .font(.caption2.weight(.bold))
            Text(report.reportType.displayName.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .foregroundStyle(XomperColors.bgDark)
        .padding(.horizontal, XomperTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(report.reportType.accentColor)
        .clipShape(Capsule())
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
