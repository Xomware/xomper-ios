import Foundation

/// Drives the Admin → Tables + Audit sub-screens (F4).
///
/// Single store covering three related surfaces — Users list +
/// editor, Leagues list + editor, Audit feed + detail — because
/// they share the same wire client + lifecycle (admin-only, fetched
/// on push, never bootstrap-cached). Splitting into three would
/// triple the boilerplate without buying isolation; the three
/// surfaces are intentionally tightly coupled.
///
/// All API calls go through the shared `XomperAPIClient`; tests
/// substitute a `XomperAPIClientProtocol` mock via the init.
@Observable
@MainActor
final class AdminTablesStore {

    // MARK: - Users

    private(set) var users: [WhitelistedUser] = []
    private(set) var isLoadingUsers = false
    private(set) var usersError: String?

    // MARK: - Leagues

    private(set) var leagues: [WhitelistedLeague] = []
    private(set) var isLoadingLeagues = false
    private(set) var leaguesError: String?

    // MARK: - Audit

    private(set) var auditEntries: [AuditEntry] = []
    private(set) var auditNextCursor: String?
    private(set) var isLoadingAudit = false
    private(set) var auditError: String?

    /// True when the backend signalled the `admin_audit` table hasn't
    /// been provisioned yet (manual Supabase migration pending). UI
    /// renders a dedicated empty state instead of the generic
    /// "no entries" message.
    private(set) var auditTableMissing = false

    /// True when there are no more pages — flipped to false when
    /// `next_cursor` is nil on a fetch. Used by the list's
    /// infinite-scroll trigger to short-circuit.
    var hasMoreAudit: Bool {
        auditNextCursor != nil
    }

    // MARK: - Writes

    private(set) var isSaving = false

    /// Last save success — empty string means the action completed
    /// without crashing but the wire response was empty (defensive).
    /// `nil` means no save has completed yet. Cleared by
    /// `clearLastSaveResult()` when the caller is done with it.
    private(set) var lastSaveSuccess: String?

    /// Last save error, surfaced to the inline error row in the
    /// edit forms.
    private(set) var lastSaveError: String?

    // MARK: - Dependencies

    private let apiClient: XomperAPIClientProtocol

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Users loaders

    /// Fetch the whitelisted-users list. Replaces `users` wholesale
    /// on success. Surfaces error to `usersError` on failure.
    func loadUsers() async {
        guard !isLoadingUsers else { return }
        isLoadingUsers = true
        usersError = nil
        defer { isLoadingUsers = false }

        do {
            users = try await apiClient.fetchWhitelistedUsers()
        } catch {
            usersError = error.localizedDescription
        }
    }

    // MARK: - Leagues loaders

    /// Fetch the whitelisted-leagues list. Replaces `leagues`
    /// wholesale on success.
    func loadLeagues() async {
        guard !isLoadingLeagues else { return }
        isLoadingLeagues = true
        leaguesError = nil
        defer { isLoadingLeagues = false }

        do {
            leagues = try await apiClient.fetchAdminWhitelistedLeagues()
        } catch {
            leaguesError = error.localizedDescription
        }
    }

    // MARK: - Audit loaders

    /// Load the audit feed. `reset = true` clears the current entries
    /// and cursor before fetching (used by the initial load + pull-to
    /// -refresh). `reset = false` is reserved for `loadMoreAudit` — but
    /// external callers should use that helper rather than passing
    /// `reset: false` directly.
    func loadAudit(reset: Bool = true) async {
        guard !isLoadingAudit else { return }
        isLoadingAudit = true
        if reset {
            auditError = nil
            auditEntries = []
            auditNextCursor = nil
            auditTableMissing = false
        }
        defer { isLoadingAudit = false }

        do {
            let response = try await apiClient.fetchAuditEntries(limit: 50, cursor: nil)
            auditEntries = response.rows
            auditNextCursor = response.nextCursor
            auditTableMissing = response.tableMissing
        } catch {
            auditError = error.localizedDescription
        }
    }

    /// Load the next page of audit entries. No-op when no cursor is
    /// available (we're at the end) or a load is already in flight.
    func loadMoreAudit() async {
        guard !isLoadingAudit else { return }
        guard let cursor = auditNextCursor, !cursor.isEmpty else { return }

        isLoadingAudit = true
        defer { isLoadingAudit = false }

        do {
            let response = try await apiClient.fetchAuditEntries(limit: 50, cursor: cursor)
            auditEntries.append(contentsOf: response.rows)
            auditNextCursor = response.nextCursor
        } catch {
            auditError = error.localizedDescription
        }
    }

    // MARK: - Writes

    /// Update one row of `whitelisted_users`. Only the fields the
    /// admin actually changed are sent — the backend writes one
    /// `admin_audit` row per call with the field-level diff. On
    /// success, mutates the local `users` array in place so the
    /// list reflects the new state without a follow-up fetch.
    func updateUser(
        userId: String,
        fields: [String: AdminFieldValue]
    ) async {
        guard !isSaving else { return }
        guard !fields.isEmpty else { return }

        isSaving = true
        lastSaveError = nil
        lastSaveSuccess = nil
        defer { isSaving = false }

        do {
            let response = try await apiClient.updateWhitelistedUser(
                userId: userId,
                fields: fields
            )
            applyUserFieldUpdates(userId: userId, fields: fields)
            lastSaveSuccess = response.userId
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    /// Update one row of `whitelisted_leagues`. Same flow as
    /// `updateUser`.
    func updateLeague(
        leagueId: String,
        fields: [String: AdminFieldValue]
    ) async {
        guard !isSaving else { return }
        guard !fields.isEmpty else { return }

        isSaving = true
        lastSaveError = nil
        lastSaveSuccess = nil
        defer { isSaving = false }

        do {
            let response = try await apiClient.updateWhitelistedLeague(
                leagueId: leagueId,
                fields: fields
            )
            applyLeagueFieldUpdates(leagueId: leagueId, fields: fields)
            lastSaveSuccess = response.leagueId
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    /// Clear save toast/error state. Call when navigating away from
    /// an edit screen so the next open doesn't show stale results.
    func clearLastSaveResult() {
        lastSaveSuccess = nil
        lastSaveError = nil
    }

    // MARK: - Private — in-place mutation helpers

    private func applyUserFieldUpdates(
        userId: String,
        fields: [String: AdminFieldValue]
    ) {
        guard let idx = users.firstIndex(where: { $0.updateKey == userId }) else { return }
        let existing = users[idx]
        var email = existing.email
        var displayName = existing.displayName
        var isAdmin = existing.isAdmin
        var isActive = existing.isActive

        for (key, value) in fields {
            switch (key, value) {
            case ("email", .string(let s)):         email = s
            case ("display_name", .string(let s)):  displayName = s
            case ("is_admin", .bool(let b)):        isAdmin = b
            case ("is_active", .bool(let b)):       isActive = b
            default:
                continue
            }
        }

        users[idx] = WhitelistedUser(
            id: existing.id,
            email: email,
            sleeperUsername: existing.sleeperUsername,
            sleeperUserId: existing.sleeperUserId,
            displayName: displayName,
            role: existing.role,
            isActive: isActive,
            isAdmin: isAdmin
        )
    }

    private func applyLeagueFieldUpdates(
        leagueId: String,
        fields: [String: AdminFieldValue]
    ) {
        guard let idx = leagues.firstIndex(where: { $0.leagueId == leagueId }) else { return }
        let existing = leagues[idx]
        var leagueName = existing.leagueName
        var isActive = existing.isActive
        var isDynasty = existing.isDynasty
        var hasTaxi = existing.hasTaxi

        for (key, value) in fields {
            switch (key, value) {
            case ("league_name", .string(let s)):  leagueName = s
            case ("is_active", .bool(let b)):      isActive = b
            case ("is_dynasty", .bool(let b)):     isDynasty = b
            case ("has_taxi", .bool(let b)):       hasTaxi = b
            default:
                continue
            }
        }

        leagues[idx] = WhitelistedLeague(
            id: existing.id,
            leagueId: existing.leagueId,
            leagueName: leagueName,
            season: existing.season,
            isActive: isActive,
            isDynasty: isDynasty,
            hasTaxi: hasTaxi,
            divisions: existing.divisions,
            size: existing.size
        )
    }
}
