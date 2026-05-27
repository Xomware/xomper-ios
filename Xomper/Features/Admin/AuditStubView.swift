import SwiftUI

/// Admin → Audit stub. Placeholder for F4's audit-log surface (recent
/// admin actions). Reached from the admin menu only when
/// `Config.AdminFlags.showAudit` is flipped on; defaults to hidden.
struct AuditStubView: View {
    var body: some View {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "Audit",
            message: "Coming soon (F4) — recent admin actions feed."
        )
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AuditStubView()
    }
    .preferredColorScheme(.dark)
}
