import Foundation

/// Typed input for the F3 `POST /admin/reports-flag` endpoint. The
/// backend accepts exactly these two metadata keys; passing anything
/// else returns 400. Raw values match the wire format so the API
/// client can serialize the enum directly into the request body.
///
/// See `docs/features/admin-portal/f3-redact/PLAN.md` for the full
/// flag semantics:
/// - `isRedacted` (`metadata.is_redacted=true`) — hides the report
///   from non-admin app surfaces (`/ai-reports/latest` returns 404,
///   `/ai-reports/list` filters the row out). Admin still sees
///   everything.
/// - `doNotBroadcast` (`metadata.do_not_broadcast=true`) — locks the
///   broadcast path. All three orchestrators re-read metadata right
///   before SES fan-out and abort with 409 when set.
enum ReportFlag: String, Codable, Sendable, CaseIterable {
    case isRedacted = "is_redacted"
    case doNotBroadcast = "do_not_broadcast"
}

/// Wire shape for the `POST /admin/reports-flag` response. Backend
/// returns the full updated `metadata` map after the write so the
/// client can mutate the local cached `AIReport` in place without
/// a second fetch — useful for the archive view's "Hide from app"
/// flow where the row needs to reflect the new flag immediately.
///
/// The keys mirror the Python handler (`api_admin_reports_flag`):
/// ```json
/// {
///   "Success": true,
///   "league_id": "1181789700187090944",
///   "report_type": "weekly",
///   "period": "2026W04",
///   "flag": "is_redacted",
///   "value": true,
///   "metadata": { "is_redacted": "true", "broadcast_at": "..." }
/// }
/// ```
struct ReportFlagResponse: Decodable, Sendable {
    let success: Bool
    let leagueId: String
    let reportType: String
    let period: String
    let flag: String
    let value: Bool
    /// Full updated metadata map. Dynamo collapses BOOL → string and
    /// numbers → string upstream so this is safely `[String: String]`.
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case leagueId = "league_id"
        case reportType = "report_type"
        case period
        case flag
        case value
        case metadata
    }
}
