import SwiftUI

/// Admin → Test Email sub-screen (F1).
///
/// Lets the admin send one of the latest AI Review reports (post-draft
/// / preseason / weekly) to a single whitelisted user. Used to iterate
/// on email copy without polluting broadcast state — backend handler
/// is read-only against `xomper-ai-reports` and writes a
/// `notification_log` row with `template = "ai_review_test"`.
///
/// UI:
/// - **Recipient picker** — Menu of whitelisted users from
///   `GET /admin/email-test-recipients`. Admin's own row is flagged.
/// - **Report picker** — Menu of `latestByType` reports (3 max).
/// - **Send button** — gold capsule; disabled until both pickers are
///   set + while in flight.
/// - **Toast** — green check on success, red X on error.
/// - **Receipts list** — last few email send attempts, newest-first.
struct TestEmailView: View {
    var authStore: AuthStore
    var aiReviewStore: AIReviewStore
    @State private var store = TestEmailStore()

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Test Email")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: callerSleeperId) {
                await loadAll()
            }
            .refreshable {
                await loadAll()
            }
    }

    private var callerSleeperId: String {
        authStore.sleeperUserId ?? ""
    }

    private func loadAll() async {
        async let recipients: () = store.loadRecipients()
        async let recents: () = store.loadRecentSends(sleeperUserId: callerSleeperId)
        async let postDraft: () = aiReviewStore.loadLatest(type: .postDraft)
        async let preseason: () = aiReviewStore.loadLatest(type: .preseason)
        async let weekly: () = aiReviewStore.loadLatest(type: .weekly)
        _ = await (recipients, recents, postDraft, preseason, weekly)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                pickerCard

                sendButton

                if let result = store.lastResult {
                    successToast(result)
                } else if let error = store.lastError {
                    errorToast(error)
                }

                receiptsHeader

                receiptsList
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
    }

    // MARK: - Picker card

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test Email")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Text("Send an existing AI Review report to one whitelisted user. Doesn't touch broadcast state.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            recipientPicker

            reportPicker
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private var recipientPicker: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Recipient")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(XomperColors.textMuted)

            Menu {
                if store.recipients.isEmpty {
                    Text(store.isLoadingRecipients ? "Loading…" : "No recipients available")
                } else {
                    ForEach(store.recipients) { recipient in
                        Button {
                            store.selectedRecipient = recipient
                        } label: {
                            HStack {
                                Text(recipient.displayName)
                                if recipient.isAdmin {
                                    Text("· admin")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(XomperColors.championGold)
                    Text(recipientLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(XomperColors.bgDark)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            }
            .disabled(store.isSending)

            if let error = store.recipientsError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.errorRed)
            }
        }
    }

    private var recipientLabel: String {
        if let recipient = store.selectedRecipient {
            return recipient.displayName
        }
        return store.isLoadingRecipients ? "Loading recipients…" : "Choose recipient"
    }

    private var reportPicker: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Report")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(XomperColors.textMuted)

            Menu {
                if availableReports.isEmpty {
                    Text("No reports available yet")
                } else {
                    ForEach(availableReports, id: \.id) { report in
                        Button {
                            store.selectedReport = report
                        } label: {
                            Text(reportLabel(for: report))
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(XomperColors.championGold)
                    Text(reportSelectionLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(XomperColors.bgDark)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            }
            .disabled(store.isSending)
        }
    }

    /// Latest-per-type, ordered Post-Draft → Preseason → Weekly. Filters
    /// out types that don't have a report yet so the picker only shows
    /// rows the admin can actually send.
    private var availableReports: [AIReport] {
        let order: [AIReportType] = [.postDraft, .preseason, .weekly]
        return order.compactMap { aiReviewStore.latestByType[$0] }
    }

    private var reportSelectionLabel: String {
        if let report = store.selectedReport {
            return reportLabel(for: report)
        }
        return availableReports.isEmpty ? "No reports available" : "Choose report"
    }

    private func reportLabel(for report: AIReport) -> String {
        "\(report.reportType.displayName) — \(report.period)"
    }

    // MARK: - Send button

    private var sendButton: some View {
        Button {
            Task {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                await store.sendTest(sleeperUserId: callerSleeperId)
            }
        } label: {
            HStack(spacing: XomperTheme.Spacing.xs) {
                if store.isSending {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(XomperColors.bgDark)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.caption2)
                }
                Text(store.isSending ? "Sending…" : "Send test email")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(XomperColors.bgDark)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: XomperTheme.minTouchTarget)
            .background(canSend ? XomperColors.championGold : XomperColors.championGold.opacity(0.4))
            .clipShape(Capsule())
        }
        .buttonStyle(.pressableCard)
        .disabled(!canSend)
        .padding(.horizontal, XomperTheme.Spacing.md)
        .accessibilityLabel("Send test email")
        .accessibilityHint(canSend ? "Double tap to send the selected report to the selected recipient." : "Choose a recipient and a report first.")
    }

    private var canSend: Bool {
        store.selectedRecipient != nil && store.selectedReport != nil && !store.isSending
    }

    // MARK: - Toasts

    private func successToast(_ result: TestEmailResponse) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("✓ Sent to \(result.recipientEmail)")
                .font(.caption.weight(.bold))
                .foregroundStyle(XomperColors.successGreen)
            if let messageId = result.messageId, !messageId.isEmpty {
                Text("SES message: \(messageId)")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .lineLimit(1)
            }
            Text("\(result.reportType) · \(result.reportPeriod) · template: \(result.template)")
                .font(.caption2)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .padding(XomperTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(XomperColors.successGreen.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func errorToast(_ message: String) -> some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.xs) {
            Image(systemName: "xmark.octagon.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(XomperColors.errorRed)
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.errorRed)
                .multilineTextAlignment(.leading)
        }
        .padding(XomperTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(XomperColors.errorRed.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Receipts

    private var receiptsHeader: some View {
        Text("Recent email sends · last 7 days")
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(XomperColors.textMuted)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.top, XomperTheme.Spacing.sm)
    }

    @ViewBuilder
    private var receiptsList: some View {
        if store.isLoadingRecentSends && store.recentSends.isEmpty {
            LoadingView(message: "Loading recent sends…")
                .padding(.top, XomperTheme.Spacing.md)
        } else if store.recentSends.isEmpty {
            EmptyStateView(
                icon: "tray",
                title: "No sends yet",
                message: "Test emails will appear here after you send one."
            )
            .frame(minHeight: 160)
        } else {
            ForEach(store.recentSends.prefix(10)) { entry in
                receiptRow(entry)
            }
        }
    }

    private func receiptRow(_ entry: AdminNotificationLogEntry) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "envelope.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                Text("EMAIL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.textSecondary)
                    .tracking(0.5)
                Text(entry.isSuccess ? "✓" : "✗")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(entry.isSuccess ? XomperColors.successGreen : XomperColors.errorRed)
                Spacer()
                Text(formattedTimestamp(entry.date))
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }

            if let subject = entry.subject, !subject.isEmpty {
                Text(subject)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
            }
            if let recipient = entry.recipient, !recipient.isEmpty {
                Text(recipient)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
                    .lineLimit(1)
            }
            if let err = entry.error, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.errorRed)
                    .lineLimit(2)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(
                    entry.isSuccess ? Color.clear : XomperColors.errorRed.opacity(0.4),
                    lineWidth: entry.isSuccess ? 0 : 1
                )
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm:ss a"
        return formatter.string(from: date)
    }
}
