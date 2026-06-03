import SwiftUI
import WebKit

/// Detail screen for one archived email. Renders the HTML body via
/// WKWebView (sandbox + no JavaScript) so what you see is what was
/// actually sent. Below the preview, a resend form takes a typed-in
/// recipient and fires `POST /admin/emails-resend`.
struct EmailArchiveDetailView: View {
    let id: String
    var store: EmailArchiveStore
    var router: AppRouter

    @State private var resendInput: String = ""

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Email Detail")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.selectedDetail?.id != id {
                    await store.loadDetail(id: id)
                }
            }
            .onDisappear {
                store.clearDetailState()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingDetail {
            LoadingView(message: "Loading email…")
        } else if let error = store.detailError {
            ErrorView(message: error) {
                Task { await store.loadDetail(id: id) }
            }
        } else if let detail = store.selectedDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                    metadataCard(detail)
                    htmlPreview(detail)
                    resendCard(detail)
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Metadata card

    private func metadataCard(_ detail: EmailArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            if let template = detail.template, !template.isEmpty {
                Text(template.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
            }
            Text(detail.subject)
                .font(.headline.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
            Text("Sent to \(detail.recipientEmail)")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
            Text(detail.sentAt)
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
                .monospacedDigit()
            if let messageId = detail.messageId, !messageId.isEmpty {
                Text("SES \(messageId)")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    // MARK: - HTML preview

    @ViewBuilder
    private func htmlPreview(_ detail: EmailArchiveEntry) -> some View {
        if let html = detail.htmlBody, !html.isEmpty {
            EmailHTMLPreview(html: html)
                .frame(height: 520)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        } else if let text = detail.textBody, !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(XomperColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(XomperTheme.Spacing.md)
            }
            .frame(height: 520)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        } else {
            EmptyStateView(
                icon: "doc",
                title: "No body stored",
                message: "This row was archived without an HTML or text body."
            )
        }
    }

    // MARK: - Resend card

    private func resendCard(_ detail: EmailArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Resend to")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
            Text("Re-fires this exact email (no re-rendering) to a typed-in address. The new send is also archived.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)

            TextField("name@example.com", text: $resendInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(XomperColors.bgDark)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
                .foregroundStyle(XomperColors.textPrimary)
                .disabled(store.isResending)

            Button {
                Task {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    await store.resend(toEmail: resendInput)
                }
            } label: {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    if store.isResending {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(XomperColors.bgDark)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.caption2)
                    }
                    Text(store.isResending ? "Sending…" : "Resend")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(XomperColors.bgDark)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: XomperTheme.minTouchTarget)
                .background(canResend ? XomperColors.championGold : XomperColors.championGold.opacity(0.4))
                .clipShape(Capsule())
            }
            .buttonStyle(.pressableCard)
            .disabled(!canResend)

            if let result = store.resendResult {
                Text("✓ Sent to \(result.recipientEmail)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.successGreen)
            } else if let error = store.resendError {
                Text("✗ \(error)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.errorRed)
                    .lineLimit(2)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    private var canResend: Bool {
        !store.isResending && resendInput.contains("@") && resendInput.count > 3
    }
}

// MARK: - HTML rendering host

/// Minimal WKWebView wrapper for rendering the archived HTML. No JS,
/// no remote loads — we just dump the stored string into a sandbox.
private struct EmailHTMLPreview: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.backgroundColor = UIColor.black
        view.isOpaque = false
        view.scrollView.indicatorStyle = .white
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
