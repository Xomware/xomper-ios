import SwiftUI

// MARK: - Hardcoded dates
//
// F4 ships with the 2026 offseason dates pinned in code. When the draft date
// slips or we roll into 2027 the strings below are a 1-line edit each. There
// is intentionally no `Date` math here — the card is a static informational
// surface and should never mis-render due to time zone confusion.

private let draftDateLine = "Mon, Jul 6 · 6:30pm ET"
private let draftLabel    = "2026 Rookie Draft"
private let week1DateLine = "Mon, Sep 8"
private let week1Label    = "Week 1 Kickoff"

/// Empty-state card for `StandingsView` when the NFL season is not in a
/// regular-season window (offseason, preseason, playoffs — anything where
/// `NflStateStore.isRegularSeason == false`).
///
/// Communicates "standings unlock when Week 1 starts" without lying about
/// 0-0-0 records or rendering stale data. Hardcoded date strings — see top
/// of file for the pin sites.
struct StandingsOffseasonCard: View {
    var body: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.championGold)
                .accessibilityHidden(true)

            VStack(spacing: XomperTheme.Spacing.xs) {
                Text("Standings unlock Week 1")
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Until then, the league is in the offseason.")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: XomperTheme.Spacing.sm) {
                dateRow(date: draftDateLine, label: draftLabel)
                dateRow(date: week1DateLine, label: week1Label)
            }
            .padding(.top, XomperTheme.Spacing.sm)
        }
        .padding(XomperTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .xomperShadow(.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Standings unlock Week 1. Until then, the league is in the offseason. " +
            "\(draftDateLine), \(draftLabel). \(week1DateLine), \(week1Label)."
        )
    }

    private func dateRow(date: String, label: String) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Text(date)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(label)
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .background(XomperColors.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }
}

#Preview {
    ScrollView {
        StandingsOffseasonCard()
            .padding()
    }
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
