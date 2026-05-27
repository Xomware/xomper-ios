import SwiftUI

/// Admin → Tables sub-screen (F4).
///
/// Three menu rows — Users / Leagues / Reports flags. Replaces F1's
/// `TablesStubView`. Rows reuse the same gold-stroked card chrome as
/// the parent `AdminView` menu (kept locally here so the AdminView
/// `private` row stays self-contained — F4 doesn't refactor that
/// out).
///
/// "Reports flags" routes back to the existing `AIReviewView` —
/// F3 already added redact + do-not-broadcast context menus on
/// every report row there. Building a third list view for this
/// would duplicate work for zero new capability.
struct TablesSubScreenView: View {
    var router: AppRouter
    var navStore: NavigationStore

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                sectionHeader("Tables")

                TablesMenuRow(
                    icon: "person.3.fill",
                    title: "Users",
                    subtitle: "Edit display name, email, admin and active flags",
                    action: { router.navigate(to: .adminTablesUsers) }
                )

                TablesMenuRow(
                    icon: "building.2.fill",
                    title: "Leagues",
                    subtitle: "Edit league name and active / dynasty / taxi flags",
                    action: { router.navigate(to: .adminTablesLeagues) }
                )

                TablesMenuRow(
                    icon: "flag.fill",
                    title: "Reports flags",
                    subtitle: "Manage redaction and broadcast locks in AI Review",
                    action: {
                        // Pop the inner nav stack and switch the top-level
                        // destination to AI Review — F3's redact + DNB
                        // context menus are already wired on every row.
                        router.popToRoot()
                        navStore.currentDestination = .aiReview
                    }
                )
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Tables")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(XomperColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, XomperTheme.Spacing.xs)
    }
}

// MARK: - Menu row

/// Tables sub-screen menu row. Visual parity with `AdminView`'s
/// private `AdminMenuRow` — same gold-stroked bgCard chrome,
/// pressable button style, accessibility shape.
private struct TablesMenuRow: View {
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
