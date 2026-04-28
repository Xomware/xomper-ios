import SwiftUI

/// Single source of truth for the tray-driven shell:
/// - drawer open/closed state
/// - currently-selected top-level destination
///
/// `AppRouter` continues to own the inner `NavigationStack` path for downstream
/// pushes (team detail, user profile, etc.). When the drawer changes
/// `currentDestination`, the router's path is popped to root so the new
/// destination renders cleanly.
@Observable
@MainActor
final class NavigationStore {

    // MARK: - State

    /// Whether the slide-out drawer is currently visible.
    var isDrawerOpen: Bool = false

    /// Top-level destination rendered inside `MainShell`'s NavigationStack root.
    /// Default landing destination on cold open is `.standings`.
    var currentDestination: TrayDestination = .standings

    // MARK: - Drawer toggling

    /// Open the drawer with the standard 0.25s ease animation.
    func openDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = true
        }
    }

    /// Close the drawer with the standard 0.25s ease animation.
    func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = false
        }
    }

    // MARK: - Destination selection

    /// Select a new top-level destination. Pops the inner router stack to root,
    /// changes destination, and closes the drawer — all inside one animation
    /// so the UI moves cohesively.
    ///
    /// - Parameters:
    ///   - destination: the destination to render at the root of the stack.
    ///   - router: optional router to pop. When `nil`, only state is mutated
    ///     (used by tests / previews).
    func select(_ destination: TrayDestination, router: AppRouter? = nil) {
        withAnimation(.easeInOut(duration: 0.25)) {
            router?.popToRoot()
            currentDestination = destination
            isDrawerOpen = false
        }
    }
}
