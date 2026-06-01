import SwiftUI

/// Admin portal home. F1 refactor — `AdminView` is now a `NavigationLink`
/// menu of 5 sub-screens. The pre-F1 trigger cards / activity feed /
/// test-sender card moved verbatim into `AIReviewSubScreen.swift`; F1
/// adds the new `TestEmailView` sub-screen + three "Coming soon" stubs.
///
/// Visibility:
/// - AI Review + Test Email — always visible for admin users.
/// - Tables / Logs / Audit — gated by `Config.AdminFlags.*`; default
///   off until F4/F5 land.
///
/// Backend gating is enforced server-side via the `is_admin` flag on
/// `whitelisted_users`; this view also hides the destination for
/// non-admins so they never see the menu.
struct AdminView: View {
    var authStore: AuthStore
    var leagueStore: LeagueStore
    var router: AppRouter

    var body: some View {
        Group {
            if !isAdmin {
                EmptyStateView(
                    icon: "lock.shield",
                    title: "Admin only",
                    message: "Your account doesn't have admin permission. Ask the commissioner to flip your is_admin flag."
                )
            } else {
                menu
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
    }

    private var isAdmin: Bool {
        authStore.whitelistedUser?.isAdmin == true
    }

    // MARK: - Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                AdminMenuRow(
                    icon: "sparkles",
                    title: "AI Review",
                    subtitle: "Trigger reports and view activity feed",
                    action: { router.navigate(to: .adminAIReview) }
                )

                AdminMenuRow(
                    icon: "paperplane",
                    title: "Test Email",
                    subtitle: "Send an AI Review report to one user",
                    action: { router.navigate(to: .adminTestEmail) }
                )

                if Config.AdminFlags.showCronSettings {
                    AdminMenuRow(
                        icon: "clock.badge.checkmark",
                        title: "Cron Settings",
                        subtitle: "Kill switch + test mode per scheduled lambda",
                        action: { router.navigate(to: .adminCronSettings) }
                    )
                }

                if Config.AdminFlags.showTables {
                    AdminMenuRow(
                        icon: "tablecells",
                        title: "Tables",
                        subtitle: "Edit users, leagues, and reports",
                        action: { router.navigate(to: .adminTables) }
                    )
                }

                if Config.AdminFlags.showLogs {
                    AdminMenuRow(
                        icon: "terminal",
                        title: "Logs",
                        subtitle: "CloudWatch tail and search",
                        action: { router.navigate(to: .adminLogs) }
                    )
                }

                if Config.AdminFlags.showAudit {
                    AdminMenuRow(
                        icon: "clock.arrow.circlepath",
                        title: "Audit",
                        subtitle: "Recent admin actions",
                        action: { router.navigate(to: .adminAudit) }
                    )
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }
}

// MARK: - Menu row

/// Single admin menu row. Mirrors the `ArchiveHubCard` styling from
/// the season-refocus F4 archive — same `bgCard` chrome, gold accent
/// stroke at 0.3 opacity, gold SF Symbol leading icon, chevron trailing.
private struct AdminMenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 36, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(XomperColors.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(XomperTheme.Spacing.md)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
            )
            .xomperShadow(.sm)
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle).")
        .accessibilityHint("Double tap to open")
    }
}
