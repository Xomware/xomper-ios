import Foundation

/// Drives the admin Email Archive list + detail + resend flow.
///
/// Owns:
/// - `rows` — the paginated list, newest-first
/// - `selectedDetail` — full row for the currently-open detail view
/// - `isLoading` / `error` for the list path
/// - `isLoadingDetail` / `detailError` for the detail path
/// - `isResending` / `resendResult` / `resendError` for the resend form
///
/// All API calls go through the shared `XomperAPIClientProtocol`;
/// tests swap a mock via the init.
@Observable
@MainActor
final class EmailArchiveStore {

    // MARK: - State

    private(set) var rows: [EmailArchiveEntry] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var error: String?

    private(set) var selectedDetail: EmailArchiveEntry?
    private(set) var isLoadingDetail = false
    private(set) var detailError: String?

    private(set) var isResending = false
    private(set) var resendResult: ResendEmailResponse?
    private(set) var resendError: String?

    // MARK: - Dependencies

    private let apiClient: XomperAPIClientProtocol
    private let pageSize: Int

    init(apiClient: XomperAPIClientProtocol = XomperAPIClient(), pageSize: Int = 25) {
        self.apiClient = apiClient
        self.pageSize = pageSize
    }

    // MARK: - List

    /// Wholesale reload — used on first appearance + pull-to-refresh.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.fetchEmailArchive(
                limit: pageSize,
                cursor: nil,
                recipient: nil,
                template: nil
            )
            rows = response.rows
            nextCursor = response.nextCursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Append-page — called when the last list row appears so the
    /// admin can scroll back through history.
    func loadMore() async {
        guard !isLoading, let cursor = nextCursor else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.fetchEmailArchive(
                limit: pageSize,
                cursor: cursor,
                recipient: nil,
                template: nil
            )
            rows.append(contentsOf: response.rows)
            nextCursor = response.nextCursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Detail

    func loadDetail(id: String) async {
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        detailError = nil
        selectedDetail = nil
        defer { isLoadingDetail = false }

        do {
            selectedDetail = try await apiClient.fetchEmailArchiveDetail(id: id)
        } catch {
            detailError = error.localizedDescription
        }
    }

    // MARK: - Resend

    /// Fire `POST /admin/emails-resend` against the loaded detail row
    /// to a typed-in recipient. Surfaces success in `resendResult`,
    /// failure in `resendError`. Clears previous result/error on each
    /// call so the toast UI is always current.
    func resend(toEmail: String) async {
        guard let detail = selectedDetail else { return }
        guard !isResending else { return }
        let trimmed = toEmail.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@") else {
            resendError = "Enter a valid email address."
            return
        }
        isResending = true
        resendError = nil
        resendResult = nil
        defer { isResending = false }

        do {
            let response = try await apiClient.resendArchivedEmail(
                id: detail.id,
                toEmail: trimmed
            )
            resendResult = response
        } catch {
            resendError = error.localizedDescription
        }
    }

    /// Reset state when navigating away from the detail screen so
    /// the next tap doesn't show stale resend toast.
    func clearDetailState() {
        selectedDetail = nil
        detailError = nil
        isLoadingDetail = false
        resendResult = nil
        resendError = nil
        isResending = false
    }
}
