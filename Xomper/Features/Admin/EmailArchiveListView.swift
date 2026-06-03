import SwiftUI

/// Admin → Email Archive list. Newest-first paginated list of every
/// SES send the backend has archived. Tap a row to push the detail
/// view (with HTML preview + resend form).
///
/// Empty state when no rows yet; error inline with a retry button.
struct EmailArchiveListView: View {
    var store: EmailArchiveStore
    var router: AppRouter

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Email Archive")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.rows.isEmpty {
                    await store.reload()
                }
            }
            .refreshable {
                await store.reload()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.rows.isEmpty {
            LoadingView(message: "Loading emails…")
        } else if let error = store.error, store.rows.isEmpty {
            ErrorView(message: error) {
                Task { await store.reload() }
            }
        } else if store.rows.isEmpty {
            EmptyStateView(
                icon: "tray",
                title: "No archived emails",
                message: "Every successful send shows up here once the new archive table is live."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(store.rows) { entry in
                        Button {
                            router.navigate(to: .adminEmailArchiveDetail(id: entry.id))
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.pressableCard)
                        .onAppear {
                            // Trigger pagination when the last row appears.
                            if entry.id == store.rows.last?.id,
                               store.nextCursor != nil {
                                Task { await store.loadMore() }
                            }
                        }
                    }

                    if store.isLoading {
                        ProgressView()
                            .tint(XomperColors.championGold)
                            .padding(.vertical, XomperTheme.Spacing.sm)
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        }
    }

    private func row(_ entry: EmailArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                if let template = entry.template, !template.isEmpty {
                    Text(template.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                Text(formattedSentAt(entry.sentAt))
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }
            Text(entry.subject)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(entry.recipientEmail)
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
                .lineLimit(1)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    private func formattedSentAt(_ raw: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, h:mm a"
            return out.string(from: date)
        }
        return raw
    }
}
