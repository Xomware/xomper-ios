import SwiftUI

/// Admin → Cron Settings.
///
/// List of every scheduled-notification lambda with two toggles per row:
/// `Enabled` (kill switch — no-op the lambda) and `Test mode` (restrict
/// delivery to the admin's Sleeper user only — useful for previewing
/// AI Review newsletters or recap emails before they fan out to the
/// league).
///
/// UX rules:
/// - The "Test mode" toggle is disabled (greyed) when `enabled == false`
///   so the admin doesn't toggle test-mode on a disabled cron by mistake.
/// - A prominent "Test mode active" banner pins to the top when any
///   cron has `test_mode == true` — mitigation for the "set test mode,
///   forgot to flip back" risk called out in the plan.
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
                if store.anyTestModeActive {
                    testModeBanner
                }

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
                            },
                            onToggleTestMode: { newValue in
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                Task { await store.toggleTestMode(cronKey: setting.cronKey, testMode: newValue) }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Banners

    private var testModeBanner: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "flask.fill")
                .font(.headline)
                .foregroundStyle(XomperColors.championGold)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                Text("Test mode active")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                Text("At least one cron is delivering only to the admin. Flip back before the next live send.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.championGold.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Test mode active. At least one cron is delivering only to the admin.")
    }

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

/// One cron row. Two toggles + a small spinner gutter so the layout
/// doesn't reflow when a save is in flight. The Test-mode toggle is
/// disabled when `setting.enabled == false`.
private struct CronSettingRow: View {
    let setting: CronSetting
    let isPending: Bool
    let onToggleEnabled: (Bool) -> Void
    let onToggleTestMode: (Bool) -> Void

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
                Text("Enabled")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textPrimary)
            }
            .tint(XomperColors.successGreen)

            Toggle(isOn: testModeBinding) {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text("Test mode")
                        .font(.subheadline)
                        .foregroundStyle(setting.enabled ? XomperColors.textPrimary : XomperColors.textMuted)
                    if !setting.enabled {
                        Text("Enable the cron to toggle test mode")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    } else if setting.testMode {
                        Text("Delivers only to the admin user")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.championGold)
                    }
                }
            }
            .tint(XomperColors.championGold)
            .disabled(!setting.enabled)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(minHeight: XomperTheme.minTouchTarget)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(
                    setting.testMode
                        ? XomperColors.championGold.opacity(0.4)
                        : XomperColors.championGold.opacity(0.15),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(setting.displayTitle). \(setting.enabled ? "Enabled" : "Disabled"). \(setting.testMode ? "Test mode on" : "Test mode off").")
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { setting.enabled },
            set: { onToggleEnabled($0) }
        )
    }

    private var testModeBinding: Binding<Bool> {
        Binding(
            get: { setting.testMode },
            set: { onToggleTestMode($0) }
        )
    }
}
