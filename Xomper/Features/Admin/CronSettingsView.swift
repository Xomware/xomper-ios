import SwiftUI

/// Admin → Cron Settings.
///
/// List of every scheduled-notification lambda with a single per-row
/// `Enabled` toggle (kill switch — no-op the lambda).
///
/// On-demand email previews live on the dedicated Admin → Test Email
/// screen, so there is no per-row test-mode toggle here — that passive
/// "next fire restricts recipients to admin" flag was redundant and
/// confusing. An inline hint points admins to the Test Email screen.
///
/// UX rules:
/// - Each row gets its own spinner during the per-row save POST.
/// - `tableMissing` from the backend renders a dedicated empty state
///   explaining the manual Supabase migration needs to be applied.
struct CronSettingsView: View {
    var store: CronSettingsStore

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Cron Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.settings.isEmpty {
                    await store.load()
                }
            }
            .refreshable {
                await store.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.settings.isEmpty {
            LoadingView(message: "Loading cron settings…")
        } else if let error = store.error, store.settings.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn't load settings",
                message: error
            )
        } else if store.tableMissing {
            EmptyStateView(
                icon: "tray",
                title: "Cron settings not yet provisioned",
                message: "An admin needs to apply the Supabase migration for `admin_cron_settings` via the dashboard before this view will render rows."
            )
        } else if store.settings.isEmpty {
            EmptyStateView(
                icon: "clock.badge.checkmark",
                title: "No cron settings",
                message: "Nothing scheduled yet. New crons appear here as they're added."
            )
        } else {
            list
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                previewHint

                if let lastError = store.lastError, !lastError.isEmpty {
                    saveErrorBanner(lastError)
                }

                VStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(store.settings) { setting in
                        CronSettingRow(
                            setting: setting,
                            isPending: store.pendingKeys.contains(setting.cronKey),
                            onToggleEnabled: { newValue in
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                Task { await store.toggleEnabled(cronKey: setting.cronKey, enabled: newValue) }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Hint

    private var previewHint: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "envelope.badge")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
                .accessibilityHidden(true)
            Text("To preview an email, use Admin → Test Email.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XomperTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("To preview an email, use Admin, Test Email.")
    }

    // MARK: - Banners

    private func saveErrorBanner(_ message: String) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(XomperColors.errorRed)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(XomperColors.errorRed)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.errorRed.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.errorRed.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Row

/// One cron row. A single `Enabled` kill-switch toggle + a small
/// spinner gutter so the layout doesn't reflow when a save is in flight.
private struct CronSettingRow: View {
    let setting: CronSetting
    let isPending: Bool
    let onToggleEnabled: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Text(setting.displayTitle)
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isPending {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(XomperColors.championGold)
                        .accessibilityLabel("Saving")
                }
            }

            Text(setting.cronKey)
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)
                .lineLimit(1)

            Toggle(isOn: enabledBinding) {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text("Enabled")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textPrimary)
                    if let description = setting.description, !description.isEmpty {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }
            }
            .tint(XomperColors.successGreen)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(minHeight: XomperTheme.minTouchTarget)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(setting.displayTitle). \(setting.enabled ? "Enabled" : "Disabled").")
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { setting.enabled },
            set: { onToggleEnabled($0) }
        )
    }
}
