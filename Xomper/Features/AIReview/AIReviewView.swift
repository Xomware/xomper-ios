import SwiftUI

/// AI Review archive. Newest-first list of every report the backend
/// has generated. Tapping a row pushes `AIReviewDetailView`. Pull-
/// to-refresh forces a re-fetch; the last row triggers
/// `store.loadMore()` for infinite scroll.
///
/// Until the backend's `/ai-reports/list` endpoint is live the call
/// errors out — the view renders the error inline. Once the route
/// returns an empty array the empty state appears instead.
///
/// F3 additions:
/// - Admin-only "Show redacted" toolbar toggle that includes hidden
///   reports in the listing (server already filters for non-admin).
/// - `.contextMenu` on each row with "Hide from app" / "Show in app"
///   actions backed by `store.setReportFlag(...)`. Hide presents a
///   destructive confirm dialog.
/// - REDACTED badge + 50% opacity on redacted rows when visible.
struct AIReviewView: View {
    let store: AIReviewStore
    let authStore: AuthStore
    let router: AppRouter

    /// Pending hide target — set when the admin taps "Hide from app"
    /// on a row context menu. Triggers the destructive `.alert` below.
    @State private var pendingHide: AIReport?
    /// Surfaces any flag-write failure (hide or unhide) inline at the
    /// top of the list so the admin can retry without losing context.
    @State private var flagError: String?

    private var isAdmin: Bool {
        authStore.whitelistedUser?.isAdmin == true
    }

    /// Client-side defense-in-depth filter:
    /// - Mock-draft reports are admin-only — they're internal scratch
    ///   reports that aren't meant for the league at large.
    /// - Redacted reports are stripped server-side for non-admins;
    ///   admins see them when `showRedacted` is on.
    private var visibleArchive: [AIReport] {
        store.archive.filter { report in
            if report.reportType == .mock && !isAdmin { return false }
            return !report.isRedacted || store.showRedacted
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                if let flagError {
                    Text("✗ \(flagError)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.errorRed)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                }

                if store.isLoading && store.archive.isEmpty {
                    LoadingView(message: "Loading reports…")
                        .padding(.top, XomperTheme.Spacing.xl)
                } else if let error = store.error, store.archive.isEmpty {
                    ErrorView(message: error.localizedDescription) {
                        Task { await store.loadArchive(force: true) }
                    }
                    .padding(.top, XomperTheme.Spacing.lg)
                } else if visibleArchive.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: "No reports yet",
                        message: "First one lands after the next draft."
                    )
                    .padding(.top, XomperTheme.Spacing.xl)
                } else {
                    ForEach(Array(visibleArchive.enumerated()), id: \.element.id) { idx, report in
                        AIReportCardRow(
                            report: report,
                            isAdmin: isAdmin,
                            onTap: {
                                router.navigate(to: .aiReportDetail(reportId: report.id))
                            },
                            onHide: {
                                pendingHide = report
                            },
                            onUnhide: {
                                Task { await applyFlag(report: report, value: false) }
                            }
                        )
                        .padding(.horizontal, XomperTheme.Spacing.md)
                        .onAppear {
                            // Infinite scroll: when the last visible
                            // row mounts, request the next page.
                            // No-op when the cursor is nil.
                            if idx == visibleArchive.count - 1 {
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
        .toolbar {
            // Admin-only "Show redacted" toggle — non-admin users
            // never see this control. The server-side filter strips
            // redacted rows for them regardless of the toggle state.
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: Binding(
                        get: { store.showRedacted },
                        set: { store.showRedacted = $0 }
                    )) {
                        Label("Show redacted", systemImage: "eye.slash")
                    }
                    .toggleStyle(.button)
                    .tint(XomperColors.championGold)
                }
            }
        }
        .alert(
            "Hide \(pendingHide?.displayTitle ?? "report")?",
            isPresented: Binding(
                get: { pendingHide != nil },
                set: { if !$0 { pendingHide = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingHide = nil }
            Button("Hide", role: .destructive) {
                if let target = pendingHide {
                    pendingHide = nil
                    Task { await applyFlag(report: target, value: true) }
                }
            }
        } message: {
            Text("Hides the report from the league archive. Admins can still see it and un-hide it later. Already-delivered emails are unaffected.")
        }
        .task {
            await store.loadArchive()
        }
        .refreshable {
            await store.refresh()
        }
    }

    /// Toggle `is_redacted` on a report. Wraps any error in `flagError`
    /// so the admin sees what went wrong without losing the rest of
    /// the archive state. On success the store updates the row in
    /// place, so no manual refresh is needed.
    private func applyFlag(report: AIReport, value: Bool) async {
        flagError = nil
        do {
            try await store.setReportFlag(
                report: report,
                flag: .isRedacted,
                value: value
            )
        } catch {
            flagError = error.localizedDescription
        }
    }
}

// MARK: - Row

/// Compact archive row — type chip, period, snippet, relative date.
/// Tappable card with the standard pressable feedback. F3: when
/// `report.isRedacted == true`, renders the REDACTED badge + dim
/// opacity; admin context menu exposes Hide / Show actions.
private struct AIReportCardRow: View {
    let report: AIReport
    let isAdmin: Bool
    let onTap: () -> Void
    let onHide: () -> Void
    let onUnhide: () -> Void

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
                    if report.isRedacted {
                        redactedBadge
                    }
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
        .opacity(report.isRedacted ? 0.5 : 1.0)
        .contextMenu {
            // F3 admin-only context actions. Non-admin users never see
            // a redacted row in the first place (server filter), so
            // hiding the menu behind `isAdmin` is belt + suspenders.
            if isAdmin {
                if report.isRedacted {
                    Button {
                        onUnhide()
                    } label: {
                        Label("Show in app", systemImage: "eye")
                    }
                } else {
                    Button(role: .destructive) {
                        onHide()
                    } label: {
                        Label("Hide from app", systemImage: "eye.slash")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
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

    /// Small all-caps badge surfaced next to the period when a report
    /// is hidden from non-admin surfaces. Only ever renders when the
    /// admin has toggled `showRedacted` on (the row is filtered out
    /// otherwise) so the badge is purely an admin signal.
    private var redactedBadge: some View {
        Text("REDACTED")
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(XomperColors.errorRed)
            .padding(.horizontal, XomperTheme.Spacing.xs)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(XomperColors.errorRed.opacity(0.6), lineWidth: 1)
            )
            .accessibilityLabel("Redacted")
    }

    private var accessibilityLabel: String {
        let base = "\(report.reportType.displayName) report, \(report.period)"
        return report.isRedacted ? "\(base), redacted" : base
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
