import SwiftUI

/// Admin → Logs stub. Placeholder for F5's CloudWatch surface. Reached
/// from the admin menu only when `Config.AdminFlags.showLogs` is
/// flipped on; defaults to hidden.
struct LogsStubView: View {
    var body: some View {
        EmptyStateView(
            icon: "terminal",
            title: "Logs",
            message: "Coming soon (F5) — CloudWatch tail and search."
        )
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LogsStubView()
    }
    .preferredColorScheme(.dark)
}
