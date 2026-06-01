import Foundation

/// Drives the Landing → Announcements card (public read) and the
/// Admin → Announcements sub-screen (admin CRUD).
///
/// Two parallel state machines on one store so a single instance can
/// satisfy both surfaces — the public read uses a 5-minute freshness
/// cache and falls back to `LeagueAnnouncements.current` on failure
/// (acceptance criterion: Landing never blanks). The admin surface
/// has no cache because the admin always wants fresh data after a
/// write, and is gated to admin users only.
///
/// Optimistic mutations: `create` appends to `adminAnnouncements`
/// immediately, then reconciles with the server response on success
/// (the server row carries the canonical `id` + timestamps). Failed
/// writes revert the optimistic mutation and surface the error.
@Observable
@MainActor
final class AnnouncementsStore {

    // MARK: - Public-read state (Landing)

    /// Active + non-expired rows for the public Landing card. Mutated
    /// by `load(force:)`. Empty when no read has succeeded yet.
    private(set) var announcements: [LeagueAnnouncement] = []
    private(set) var isLoading: Bool = false
    private(set) var error: String?
    private(set) var lastLoadedAt: Date?

    // MARK: - Admin state

    /// Every row (including inactive + expired) for the admin list.
    /// Mutated by `loadAdmin`, `create`, `update`, `delete`.
    private(set) var adminAnnouncements: [LeagueAnnouncement] = []
    private(set) var isLoadingAdmin: Bool = false
    private(set) var adminError: String?
    /// True when the backend signalled the `league_announcements`
    /// table hasn't been provisioned yet (manual Supabase migration
    /// pending). UI renders a dedicated empty state in that case.
    private(set) var tableMissing: Bool = false

    /// Per-row in-flight tracker for admin mutations. Used by the
    /// list view to show a small spinner on the row currently being
    /// deleted, and to dedupe rapid taps.
    private(set) var pendingIds: Set<UUID> = []

    /// Last write error surfaced to the admin edit/list view. Cleared
    /// at the start of the next write.
    private(set) var lastWriteError: String?

    // MARK: - Dependencies

    /// 5-minute freshness gate for `load()`. The admin's "+ New" flow
    /// + pull-to-refresh on Landing both bypass with `force: true`.
    private let cacheLifetime: TimeInterval = 5 * 60

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Public read

    /// Fetch the public-read announcements list. Respects a 5-minute
    /// freshness cache unless `force == true`. On error, falls back
    /// to `LeagueAnnouncements.current` so the Landing card always
    /// renders something — keeps the acceptance criterion of "Landing
    /// never blanks" honest even when the backend is down.
    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastLoadedAt,
           Date().timeIntervalSince(lastLoadedAt) < cacheLifetime,
           !announcements.isEmpty {
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.fetchAnnouncements()
            announcements = response.rows
            lastLoadedAt = Date()
        } catch {
            self.error = error.localizedDescription
            // Fallback: only seed from the hardcoded list if we have
            // nothing else to show. Preserves any previously-loaded
            // server rows across transient network blips.
            if announcements.isEmpty {
                announcements = LeagueAnnouncements.current
            }
        }
    }

    // MARK: - Admin read

    /// Fetch every row for the admin list (including inactive +
    /// expired). No cache — the admin always wants fresh data.
    func loadAdmin() async {
        guard !isLoadingAdmin else { return }
        isLoadingAdmin = true
        adminError = nil
        defer { isLoadingAdmin = false }

        do {
            let response = try await apiClient.fetchAdminAnnouncements()
            adminAnnouncements = response.rows
            tableMissing = response.tableMissing
        } catch {
            adminError = error.localizedDescription
        }
    }

    // MARK: - Admin writes

    /// Create one row. Optimistic: appends a placeholder to the
    /// admin list immediately with a client-side UUID, then replaces
    /// it with the server's resolved row on success. Reverts on
    /// failure and re-throws so the caller can stay on the form.
    @discardableResult
    func create(
        title: String,
        body: String,
        priority: LeagueAnnouncement.Priority,
        expiresAt: Date?,
        isActive: Bool,
        displayOrder: Int
    ) async throws -> LeagueAnnouncement {
        let placeholderId = UUID()
        let placeholder = LeagueAnnouncement(
            id: placeholderId,
            title: title,
            body: body,
            priority: priority,
            expiresAt: expiresAt,
            isActive: isActive,
            displayOrder: displayOrder,
            createdAt: Date(),
            updatedAt: Date()
        )
        adminAnnouncements.insert(placeholder, at: 0)
        pendingIds.insert(placeholderId)
        lastWriteError = nil
        defer { pendingIds.remove(placeholderId) }

        do {
            let response = try await apiClient.createAnnouncement(
                title: title,
                body: body,
                priority: priority.rawValue,
                expiresAt: expiresAt,
                isActive: isActive,
                displayOrder: displayOrder
            )
            // Swap the placeholder for the server-resolved row.
            if let idx = adminAnnouncements.firstIndex(where: { $0.id == placeholderId }) {
                adminAnnouncements[idx] = response.row
            } else {
                // Defensive — placeholder was somehow lost. Insert the
                // canonical row at the top.
                adminAnnouncements.insert(response.row, at: 0)
            }
            // Mirror onto public list if the new row is active +
            // not yet expired (saves a follow-up `load(force: true)`).
            if response.row.isActive,
               (response.row.expiresAt.map { $0 > Date() } ?? true) {
                announcements.insert(response.row, at: 0)
            }
            return response.row
        } catch {
            // Revert the optimistic insertion.
            adminAnnouncements.removeAll { $0.id == placeholderId }
            lastWriteError = error.localizedDescription
            throw error
        }
    }

    /// Update one row by id. Optimistic — applies the diff in place
    /// immediately, then replaces the row with the server response on
    /// success. Reverts on failure and re-throws.
    @discardableResult
    func update(
        id: UUID,
        fields: [String: AdminFieldValue]
    ) async throws -> LeagueAnnouncement {
        guard let idx = adminAnnouncements.firstIndex(where: { $0.id == id }) else {
            throw AnnouncementsStoreError.notFound
        }
        let original = adminAnnouncements[idx]
        adminAnnouncements[idx] = Self.applyFields(to: original, fields: fields)
        pendingIds.insert(id)
        lastWriteError = nil
        defer { pendingIds.remove(id) }

        do {
            let response = try await apiClient.updateAnnouncement(id: id, fields: fields)
            // Reconcile with the server row.
            if let confirmIdx = adminAnnouncements.firstIndex(where: { $0.id == id }) {
                adminAnnouncements[confirmIdx] = response.row
            }
            // Mirror onto the public list if visible there.
            if let pubIdx = announcements.firstIndex(where: { $0.id == id }) {
                if response.row.isActive,
                   (response.row.expiresAt.map { $0 > Date() } ?? true) {
                    announcements[pubIdx] = response.row
                } else {
                    announcements.remove(at: pubIdx)
                }
            }
            return response.row
        } catch {
            // Revert the optimistic mutation.
            if let revertIdx = adminAnnouncements.firstIndex(where: { $0.id == id }) {
                adminAnnouncements[revertIdx] = original
            }
            lastWriteError = error.localizedDescription
            throw error
        }
    }

    /// Soft-delete one row (backend flips `is_active = false`).
    /// Optimistic: flips locally first, then awaits the server. On
    /// failure, restores the row to its prior active state.
    func delete(id: UUID) async throws {
        guard let idx = adminAnnouncements.firstIndex(where: { $0.id == id }) else {
            throw AnnouncementsStoreError.notFound
        }
        let original = adminAnnouncements[idx]
        adminAnnouncements[idx] = LeagueAnnouncement(
            id: original.id,
            title: original.title,
            body: original.body,
            priority: original.priority,
            expiresAt: original.expiresAt,
            isActive: false,
            displayOrder: original.displayOrder,
            createdAt: original.createdAt,
            updatedAt: Date()
        )
        // Drop from the public list immediately — the backend will
        // do the same on its next read, but the UI shouldn't lag.
        announcements.removeAll { $0.id == id }

        pendingIds.insert(id)
        lastWriteError = nil
        defer { pendingIds.remove(id) }

        do {
            let response = try await apiClient.deleteAnnouncement(id: id)
            if let confirmIdx = adminAnnouncements.firstIndex(where: { $0.id == id }) {
                adminAnnouncements[confirmIdx] = response.row
            }
        } catch {
            // Revert the optimistic flip — restore the original row
            // back into both admin + public lists.
            if let revertIdx = adminAnnouncements.firstIndex(where: { $0.id == id }) {
                adminAnnouncements[revertIdx] = original
            }
            if original.isActive {
                announcements.insert(original, at: 0)
            }
            lastWriteError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Misc

    /// Clear the last write error. Call when navigating away from a
    /// form so the next open doesn't show stale state.
    func clearLastWriteError() {
        lastWriteError = nil
    }

    // MARK: - Private — field-merge helper

    /// Apply a partial field diff to a `LeagueAnnouncement`. Mirrors
    /// the backend's allowlist (`title`, `body`, `priority`,
    /// `expires_at`, `is_active`, `display_order`). Unknown keys are
    /// ignored — the server is the hard backstop.
    private static func applyFields(
        to original: LeagueAnnouncement,
        fields: [String: AdminFieldValue]
    ) -> LeagueAnnouncement {
        var title = original.title
        var body = original.body
        var priority = original.priority
        var expiresAt = original.expiresAt
        var isActive = original.isActive
        var displayOrder = original.displayOrder

        for (key, value) in fields {
            switch (key, value) {
            case ("title", .string(let s)):        title = s
            case ("body", .string(let s)):         body = s
            case ("priority", .string(let s)):     priority = LeagueAnnouncement.Priority(rawValue: s) ?? priority
            case ("expires_at", .string(let s)):
                expiresAt = Self.parseISODate(s)
            case ("expires_at", .null):            expiresAt = nil
            case ("is_active", .bool(let b)):      isActive = b
            case ("display_order", .int(let i)):   displayOrder = i
            default:
                continue
            }
        }

        return LeagueAnnouncement(
            id: original.id,
            title: title,
            body: body,
            priority: priority,
            expiresAt: expiresAt,
            isActive: isActive,
            displayOrder: displayOrder,
            createdAt: original.createdAt,
            updatedAt: Date()
        )
    }

    /// Permissive ISO8601 parser — handles with and without fractional
    /// seconds (Postgres `timestamptz` can serialise either way).
    private static func parseISODate(_ raw: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: raw)
    }
}

/// Errors thrown by `AnnouncementsStore` mutations.
enum AnnouncementsStoreError: Error, LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: "Announcement not found in the local list. Refresh and try again."
        }
    }
}
