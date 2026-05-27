import SwiftUI

/// Admin → Tables stub. Placeholder for F4's editor surface (users /
/// leagues / reports). Reached from the admin menu only when
/// `Config.AdminFlags.showTables` is flipped on; defaults to hidden.
struct TablesStubView: View {
    var body: some View {
        EmptyStateView(
            icon: "tablecells",
            title: "Tables",
            message: "Coming soon (F4) — Supabase + Dynamo admin editing."
        )
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Tables")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TablesStubView()
    }
    .preferredColorScheme(.dark)
}
