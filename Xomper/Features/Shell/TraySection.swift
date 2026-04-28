import Foundation

/// A grouping of `TrayDestination`s rendered together in the drawer with
/// an optional uppercase section header.
struct TraySection: Identifiable {
    /// Optional section header (uppercase muted caption). When `nil`, entries
    /// render flush with no header.
    let title: String?

    /// Destinations in this section, rendered top-to-bottom.
    let entries: [TrayDestination]

    /// Stable identity for `ForEach` — derived from title (or first entry's
    /// title when no section title is provided).
    var id: String { title ?? entries.first.map(\.title) ?? "section" }
}
