import SwiftUI

/// Full-screen dim overlay shown behind the drawer while it's open.
/// Tap to close — also accessibility-labelled as a button for VoiceOver.
struct DrawerScrim: View {
    let navStore: NavigationStore

    var body: some View {
        if navStore.isDrawerOpen {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    navStore.closeDrawer()
                }
                .accessibilityLabel("Close menu")
                .accessibilityHint("Double-tap to dismiss")
                .accessibilityAddTraits(.isButton)
                .transition(.opacity)
        }
    }
}
