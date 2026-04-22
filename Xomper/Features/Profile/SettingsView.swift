import SwiftUI
@preconcurrency import UserNotifications

struct SettingsView: View {
    var pushManager: PushNotificationManager

    @State private var notificationsEnabled = false
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                notificationsSection
                aboutSection
            }
            .padding(XomperTheme.Spacing.md)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await checkNotificationStatus()
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Notifications")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.leading, XomperTheme.Spacing.xs)

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.title3)
                        .foregroundStyle(XomperColors.championGold)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                        Text("Push Notifications")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(XomperColors.textPrimary)

                        Text(notificationStatusMessage)
                            .font(.caption)
                            .foregroundStyle(XomperColors.textMuted)
                    }

                    Spacer()

                    if notificationStatus == .denied {
                        Button("Open Settings") {
                            openAppSettings()
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(XomperColors.championGold)
                    } else {
                        Toggle("", isOn: $notificationsEnabled)
                            .tint(XomperColors.championGold)
                            .labelsHidden()
                            .onChange(of: notificationsEnabled) { _, newValue in
                                Task {
                                    if newValue {
                                        await pushManager.requestPermission()
                                    }
                                    await checkNotificationStatus()
                                }
                            }
                    }
                }
                .padding(XomperTheme.Spacing.md)
            }
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        }
    }

    private var notificationStatusMessage: String {
        switch notificationStatus {
        case .authorized:
            "Rule proposals, votes, and taxi steal alerts"
        case .denied:
            "Notifications are disabled in System Settings"
        case .provisional:
            "Delivering quietly"
        case .notDetermined:
            "Enable to get alerts for league activity"
        default:
            "Enable to get alerts for league activity"
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("About")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.leading, XomperTheme.Spacing.xs)

            VStack(spacing: 0) {
                aboutRow(label: "Version", value: appVersion)
                Divider().overlay(XomperColors.surfaceLight)
                aboutRow(label: "Build", value: buildNumber)
                Divider().overlay(XomperColors.surfaceLight)
                aboutRow(label: "Sleeper API", value: "api.sleeper.app")
            }
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textMuted)
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .frame(minHeight: XomperTheme.minTouchTarget)
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(pushManager: PushNotificationManager.shared)
    }
    .preferredColorScheme(.dark)
}
