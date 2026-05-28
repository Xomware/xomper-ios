import Foundation

// MARK: - Protocol

protocol XomperAPIClientProtocol: Sendable {
    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String], userIds: [String]) async throws
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], userIds: [String], leagueName: String) async throws
    func registerDevice(userId: String, deviceToken: String) async throws
    func unregisterDevice(userId: String, deviceToken: String) async throws

    // Admin portal
    func adminListNotifications(sleeperUserId: String, daysBack: Int, kind: String?, status: String?, limit: Int) async throws -> AdminNotificationsResponse
    func adminTestSend(sleeperUserId: String, email: String?, kind: String, channels: [String]) async throws -> AdminTestSendResponse
    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient]
    func sendTestEmail(recipientSleeperUserId: String, reportId: String) async throws -> TestEmailResponse

    // AI Review
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport?
    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse
    func fetchAIReportByPeriod(type: AIReportType, period: String) async throws -> AIReport?
    func fetchMockDrafts() async throws -> [AIReport]
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse

    // Admin: report metadata flags (F3)
    func setReportFlag(
        leagueId: String,
        reportType: AIReportType,
        period: String,
        flag: ReportFlag,
        value: Bool
    ) async throws -> ReportFlagResponse

    // Admin: tables + audit (F4)
    func fetchWhitelistedUsers() async throws -> [WhitelistedUser]
    func updateWhitelistedUser(userId: String, fields: [String: AdminFieldValue]) async throws -> UserUpdateResponse
    func fetchAdminWhitelistedLeagues() async throws -> [WhitelistedLeague]
    func updateWhitelistedLeague(leagueId: String, fields: [String: AdminFieldValue]) async throws -> LeagueUpdateResponse
    func fetchAuditEntries(limit: Int, cursor: String?) async throws -> AuditListResponse
}

// MARK: - Request Payloads

struct RuleProposalEmailPayload: Encodable, Sendable {
    let title: String
    let description: String
    let proposedByUsername: String
    let leagueName: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case proposedByUsername = "proposed_by_username"
        case leagueName = "league_name"
    }
}

struct TaxiStealerPayload: Encodable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct TaxiPlayerPayload: Encodable, Sendable {
    let firstName: String
    let lastName: String
    let position: String
    let team: String
    let playerImageUrl: String
    let teamLogoUrl: String
    let pickCost: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case position
        case team
        case playerImageUrl = "player_image_url"
        case teamLogoUrl = "team_logo_url"
        case pickCost = "pick_cost"
    }
}

struct TaxiOwnerPayload: Encodable, Sendable {
    let displayName: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case email
    }
}

/// Wire shape for `POST /admin/ai-review-weekly-trigger`.
///
/// `week` uses `encodeIfPresent` so when `nil` is passed the JSON key
/// is omitted entirely — the backend then defaults to its
/// `nfl_state.week - 1` resolution. Sending `"week": null` would be
/// interpreted by some Pydantic configs as an explicit override.
struct WeeklyTriggerRequest: Encodable, Sendable {
    let week: Int?
    let dryRun: Bool
    let force: Bool

    enum CodingKeys: String, CodingKey {
        case week
        case dryRun = "dry_run"
        case force
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(week, forKey: .week)
        try container.encode(dryRun, forKey: .dryRun)
        try container.encode(force, forKey: .force)
    }
}

// MARK: - Response

struct XomperAPIResponse: Decodable, Sendable {
    let success: Bool
    let message: String

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case message = "Message"
    }
}

// MARK: - Admin Portal

/// Single row from `/admin/notifications`. Mirrors the
/// xomper-notification-log DynamoDB schema. Channel-specific fields
/// (`recipient` / `subject` for email, `userId` / `title` / `body`
/// for push) are decoded leniently — server returns whatever was
/// captured at send time.
struct AdminNotificationLogEntry: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    let day: String
    let epochMs: Int
    let kind: String
    let status: String
    let userId: String?
    let title: String?
    let body: String?
    let category: String?
    let recipient: String?
    let subject: String?
    let bodySnippet: String?
    let handler: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, day, kind, status, title, body, category, recipient, subject, handler, error
        case epochMs = "epoch_ms"
        case userId = "user_id"
        case bodySnippet = "body_snippet"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        day = (try? c.decode(String.self, forKey: .day)) ?? ""
        epochMs = (try? c.decode(Int.self, forKey: .epochMs)) ?? 0
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? ""
        userId = try? c.decodeIfPresent(String.self, forKey: .userId)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        recipient = try? c.decodeIfPresent(String.self, forKey: .recipient)
        subject = try? c.decodeIfPresent(String.self, forKey: .subject)
        bodySnippet = try? c.decodeIfPresent(String.self, forKey: .bodySnippet)
        handler = try? c.decodeIfPresent(String.self, forKey: .handler)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }

    var date: Date {
        Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
    }

    var isSuccess: Bool {
        status == "success"
    }

    var isPush: Bool { kind == "push" }
    var isEmail: Bool { kind == "email" }
}

struct AdminNotificationsResponse: Decodable, Sendable {
    let rows: [AdminNotificationLogEntry]
    let count: Int
}

// MARK: - AI Review

/// Wraps `/ai-reports/latest`. Backend returns
/// `{ "report": {...} | null }` and the client unwraps `report` to a
/// nilable `AIReport`.
struct AIReportLatestResponse: Decodable, Sendable {
    let report: AIReport?
}

/// Wraps `/ai-reports/list`. `rows` is newest-first via the
/// `created-at-index` GSI; `nextCursor` is the opaque pagination
/// token returned by Dynamo.
struct AIReportsListResponse: Decodable, Sendable {
    let rows: [AIReport]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case rows
        case nextCursor = "next_cursor"
    }
}

struct AdminTestSendResponse: Decodable, Sendable {
    let kind: String
    let pushSent: Int
    let emailSent: Int

    enum CodingKeys: String, CodingKey {
        case kind
        case pushSent = "push_sent"
        case emailSent = "email_sent"
    }
}

// MARK: - Admin Test Email (F1)

/// One whitelisted user eligible to receive an admin-triggered test
/// email. Mirrors the row shape returned by
/// `GET /admin/email-test-recipients`. `isAdmin` is included so the
/// picker can flag the admin's own row (useful when iterating tone
/// — sending to yourself avoids spamming the league).
struct TestEmailRecipient: Codable, Identifiable, Sendable, Hashable {
    let userId: String
    let displayName: String
    let email: String
    let isAdmin: Bool

    /// Identity for `ForEach` — Sleeper user IDs are unique within
    /// the league.
    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case email
        case isAdmin = "is_admin"
    }
}

/// Wraps `GET /admin/email-test-recipients`. Backend returns the
/// rows under a top-level `recipients` key alongside a count.
struct TestEmailRecipientsResponse: Decodable, Sendable {
    let recipients: [TestEmailRecipient]
}

/// Successful response from `POST /admin/email-test`. Carries the
/// SES message id (when available) so the iOS receipts list can
/// cross-reference against the notification log row.
struct TestEmailResponse: Codable, Sendable {
    let recipientEmail: String
    let messageId: String?
    let sentAt: String
    let template: String
    let reportType: String
    let reportPeriod: String

    enum CodingKeys: String, CodingKey {
        case recipientEmail = "recipient_email"
        case messageId = "message_id"
        case sentAt = "sent_at"
        case template
        case reportType = "report_type"
        case reportPeriod = "report_period"
    }
}

// MARK: - Admin Tables + Audit (F4)

/// Strongly-typed value for an `updateUser` / `updateLeague` field
/// payload. The wire body is `{"fields": {...}}` with heterogeneous
/// types — strings for names + emails, bools for is_admin /
/// is_active / is_dynasty / has_taxi. Wrapping the values in this
/// enum keeps the API surface type-safe up to the JSONSerialization
/// hop, which expects `Any`.
enum AdminFieldValue: Sendable, Hashable {
    case string(String)
    case bool(Bool)

    /// Render this value as a JSONSerialization-compatible scalar.
    var jsonValue: Any {
        switch self {
        case .string(let s): return s
        case .bool(let b):   return b
        }
    }
}

/// Wraps `GET /admin/users-list`. Backend returns rows under the
/// top-level `users` key (per the F4 plan's API client decodables).
struct UsersListResponse: Decodable, Sendable {
    let users: [WhitelistedUser]
    let count: Int?
}

/// Wraps `POST /admin/users-update`. Backend returns the diff
/// (before / after) so the iOS audit feed can render the change
/// without a second fetch. `Success` matches the canonical
/// XomperAPIResponse convention.
struct UserUpdateResponse: Decodable, Sendable {
    let success: Bool
    let userId: String
    let before: JSONValue?
    let after: JSONValue?

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case userId = "user_id"
        case before
        case after
    }
}

/// Wraps `GET /admin/leagues-list`. Same shape as `UsersListResponse`
/// but for `whitelisted_leagues` rows.
struct AdminLeaguesListResponse: Decodable, Sendable {
    let leagues: [WhitelistedLeague]
    let count: Int?
}

/// Wraps `POST /admin/leagues-update`. Mirrors `UserUpdateResponse`.
struct LeagueUpdateResponse: Decodable, Sendable {
    let success: Bool
    let leagueId: String
    let before: JSONValue?
    let after: JSONValue?

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case leagueId = "league_id"
        case before
        case after
    }
}

/// Wraps `GET /admin/audit-list`. `tableMissing` is set true when
/// the Supabase `admin_audit` table hasn't been provisioned yet
/// (manual migration pending) — iOS renders a friendly explanatory
/// empty state instead of crashing or showing a generic empty list.
struct AuditListResponse: Decodable, Sendable {
    let success: Bool
    let count: Int
    let rows: [AuditEntry]
    let nextCursor: String?
    let tableMissing: Bool

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case count
        case rows
        case nextCursor = "next_cursor"
        case tableMissing = "table_missing"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        self.count = (try? c.decode(Int.self, forKey: .count)) ?? 0
        self.rows = (try? c.decode([AuditEntry].self, forKey: .rows)) ?? []
        self.nextCursor = try? c.decodeIfPresent(String.self, forKey: .nextCursor)
        self.tableMissing = (try? c.decodeIfPresent(Bool.self, forKey: .tableMissing)) ?? false
    }

    /// Memberwise init for tests / previews.
    init(success: Bool, count: Int, rows: [AuditEntry], nextCursor: String?, tableMissing: Bool) {
        self.success = success
        self.count = count
        self.rows = rows
        self.nextCursor = nextCursor
        self.tableMissing = tableMissing
    }
}

// MARK: - Errors

enum XomperAPIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case encodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid API URL"
        case .httpError(let code):
            "API returned status \(code)"
        case .encodingError(let error):
            "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Concrete Implementation

final class XomperAPIClient: XomperAPIClientProtocol {
    private let baseURL: String
    private let authToken: String
    private let session: URLSession
    private let encoder: JSONEncoder

    init(
        baseURL: String = Config.apiGatewayURL,
        authToken: String = "",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
        self.encoder = JSONEncoder()
    }

    // MARK: - Rule Emails

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String], userIds: [String]) async throws {
        let body: [String: Any] = [
            "proposal": [
                "title": proposal.title,
                "description": proposal.description,
                "proposed_by_username": proposal.proposedByUsername,
                "league_name": proposal.leagueName
            ],
            "recipients": recipients,
            "user_ids": userIds
        ]
        try await post("/email/rule-proposal", body: body)
    }

    func sendRuleAcceptedEmail(
        proposal: RuleProposalEmailPayload,
        approvedBy: [String],
        rejectedBy: [String],
        recipients: [String],
        userIds: [String]
    ) async throws {
        let body: [String: Any] = [
            "proposal": [
                "title": proposal.title,
                "description": proposal.description,
                "proposed_by_username": proposal.proposedByUsername,
                "league_name": proposal.leagueName
            ],
            "approved_by": approvedBy,
            "rejected_by": rejectedBy,
            "recipients": recipients,
            "user_ids": userIds
        ]
        try await post("/email/rule-accept", body: body)
    }

    func sendRuleDeniedEmail(
        proposal: RuleProposalEmailPayload,
        approvedBy: [String],
        rejectedBy: [String],
        recipients: [String],
        userIds: [String]
    ) async throws {
        let body: [String: Any] = [
            "proposal": [
                "title": proposal.title,
                "description": proposal.description,
                "proposed_by_username": proposal.proposedByUsername,
                "league_name": proposal.leagueName
            ],
            "approved_by": approvedBy,
            "rejected_by": rejectedBy,
            "recipients": recipients,
            "user_ids": userIds
        ]
        try await post("/email/rule-deny", body: body)
    }

    // MARK: - Taxi Steal Email

    func sendTaxiStealEmail(
        stealer: TaxiStealerPayload,
        player: TaxiPlayerPayload,
        owner: TaxiOwnerPayload,
        recipients: [String],
        userIds: [String],
        leagueName: String
    ) async throws {
        let body: [String: Any] = [
            "stealer": ["display_name": stealer.displayName],
            "player": [
                "first_name": player.firstName,
                "last_name": player.lastName,
                "position": player.position,
                "team": player.team,
                "player_image_url": player.playerImageUrl,
                "team_logo_url": player.teamLogoUrl,
                "pick_cost": player.pickCost
            ],
            "owner": [
                "display_name": owner.displayName,
                "email": owner.email
            ],
            "recipients": recipients,
            "user_ids": userIds,
            "league_name": leagueName
        ]
        try await post("/email/taxi", body: body)
    }

    // MARK: - Device Registration

    func registerDevice(userId: String, deviceToken: String) async throws {
        let body: [String: Any] = [
            "user_id": userId,
            "device_token": deviceToken,
            "platform": "ios"
        ]
        try await post("/device/register", body: body)
    }

    func unregisterDevice(userId: String, deviceToken: String) async throws {
        let body: [String: Any] = [
            "user_id": userId,
            "device_token": deviceToken
        ]
        try await post("/device/unregister", body: body)
    }

    // MARK: - Admin Portal

    func adminListNotifications(
        sleeperUserId: String,
        daysBack: Int = 7,
        kind: String? = nil,
        status: String? = nil,
        limit: Int = 100
    ) async throws -> AdminNotificationsResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "sleeper_user_id", value: sleeperUserId),
            URLQueryItem(name: "days_back", value: String(daysBack)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let kind, !kind.isEmpty {
            items.append(URLQueryItem(name: "kind", value: kind))
        }
        if let status, !status.isEmpty {
            items.append(URLQueryItem(name: "status", value: status))
        }
        return try await get("/admin/notifications", queryItems: items)
    }

    func adminTestSend(
        sleeperUserId: String,
        email: String?,
        kind: String,
        channels: [String] = ["push", "email"]
    ) async throws -> AdminTestSendResponse {
        var body: [String: Any] = [
            "sleeper_user_id": sleeperUserId,
            "kind": kind,
            "channels": channels,
        ]
        if let email, !email.isEmpty {
            body["email"] = email
        }
        return try await postDecoding("/admin/test-send", body: body)
    }

    /// Admin-only: list whitelisted users eligible to receive a test
    /// email. Backed by `GET /admin/email-test-recipients` (F1) which
    /// reads the active rows from Supabase `whitelisted_users`. The
    /// picker on `TestEmailView` consumes this list.
    func fetchTestEmailRecipients() async throws -> [TestEmailRecipient] {
        let response: TestEmailRecipientsResponse = try await get(
            "/admin/email-test-recipients",
            queryItems: []
        )
        return response.recipients
    }

    /// Admin-only: deliver one existing AI Review report as an email
    /// to one whitelisted user. `reportId` matches `AIReport.id`
    /// (composite `pk|sk`); backend splits on `|` to load the row
    /// from Dynamo. **Never** writes `metadata.broadcast_at` on the
    /// report — strictly read-only against `xomper-ai-reports`.
    func sendTestEmail(
        recipientSleeperUserId: String,
        reportId: String
    ) async throws -> TestEmailResponse {
        let body: [String: Any] = [
            "recipient_user_id": recipientSleeperUserId,
            "report_id": reportId,
        ]
        return try await postDecoding("/admin/email-test", body: body)
    }

    // MARK: - AI Review

    /// Latest report of a given type for the active whitelisted
    /// league. Backend resolves the league via Supabase, so the
    /// caller doesn't pass a leagueId. Returns `nil` when no report
    /// of that type exists yet (empty state on a fresh table).
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport? {
        let items: [URLQueryItem] = [
            URLQueryItem(name: "type", value: type.rawValue),
        ]
        let response: AIReportLatestResponse = try await get("/ai-reports/latest", queryItems: items)
        return response.report
    }

    /// Paginated archive across all report types (or filtered to one
    /// type when `type` is non-nil). `limit` caps the per-page row
    /// count; `cursor` is the opaque token returned by a previous
    /// call's `nextCursor`.
    func fetchAIReportsList(
        type: AIReportType? = nil,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> AIReportsListResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let type {
            items.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await get("/ai-reports/list", queryItems: items)
    }

    /// Look up a single AI report by its `(type, period)` pair. The
    /// list endpoint doesn't yet accept a `period=` query param, so
    /// this lists by type and client-side picks the row whose
    /// `period` matches. Returns `nil` when no row matches — caller
    /// can render an empty state. Walks the cursor if necessary so a
    /// later-period report deep in the archive is still resolvable.
    ///
    /// Used by `MatchupsView` to fetch the weekly recap whose
    /// `metadata.matchups[]` carries the per-matchup blurbs for a
    /// past, scored week (e.g. `period = "2025W04"`).
    func fetchAIReportByPeriod(
        type: AIReportType,
        period: String
    ) async throws -> AIReport? {
        var cursor: String? = nil
        // Cap the walk so a misconfigured backend can't loop us.
        // 5 pages × 20 rows = 100 reports of a single type, which is
        // far more than the league produces in a season.
        for _ in 0..<5 {
            let response = try await fetchAIReportsList(
                type: type,
                limit: 20,
                cursor: cursor
            )
            if let hit = response.rows.first(where: { $0.period == period }) {
                return hit
            }
            guard let next = response.nextCursor, !next.isEmpty else {
                return nil
            }
            cursor = next
        }
        return nil
    }

    /// Convenience wrapper over `fetchAIReportsList(type: .mock)` —
    /// the mock-draft surface always wants every mock the backend has
    /// produced for the active draft year, so we drain the cursor up
    /// front instead of building cursor state into `MocksView`. The
    /// per-personality count is small (3 today, ~handful at most), so
    /// the all-pages walk is cheap.
    func fetchMockDrafts() async throws -> [AIReport] {
        var all: [AIReport] = []
        var cursor: String? = nil
        for _ in 0..<5 {
            let response = try await fetchAIReportsList(
                type: .mock,
                limit: 20,
                cursor: cursor
            )
            all.append(contentsOf: response.rows)
            guard let next = response.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return all
    }

    /// Admin-only: fires the backend `notif_ai_review_postdraft`
    /// lambda. With `dryRun = true` (default) the report is written
    /// to Dynamo and delivered only to the admin user (single-user
    /// SES + SNS) so tone can be reviewed before broadcast. With
    /// `dryRun = false` + `force = true` the same row is overwritten
    /// and broadcast to all 12 managers.
    ///
    /// Backend path was flattened to `/admin/ai-review-postdraft-trigger`
    /// in infra PR #104 (API GW path-builder doesn't handle 3-segment
    /// parents cleanly; flattening was the smallest change).
    func triggerPostDraftAIReview(
        dryRun: Bool,
        force: Bool
    ) async throws -> AIReviewTriggerResponse {
        let body: [String: Any] = [
            "dry_run": dryRun,
            "force": force,
        ]
        return try await postDecoding("/admin/ai-review-postdraft-trigger", body: body)
    }

    /// Admin-only: fires the backend `notif_ai_review_preseason` lambda.
    /// Same shape as `triggerPostDraftAIReview` — with `dryRun = true`
    /// (default) the report is written to Dynamo and delivered only to
    /// the admin user for tone calibration. With `dryRun = false` +
    /// `force = true` the same row is overwritten and broadcast to all
    /// 12 managers.
    ///
    /// Backend route is `/admin/ai-review-preseason-trigger`, registered
    /// alongside the post-draft trigger in F2's infra PR.
    func triggerPreseasonAIReview(
        dryRun: Bool,
        force: Bool
    ) async throws -> AIReviewTriggerResponse {
        let body: [String: Any] = [
            "dry_run": dryRun,
            "force": force,
        ]
        return try await postDecoding("/admin/ai-review-preseason-trigger", body: body)
    }

    /// Admin-only: fires the backend `notif_ai_review_weekly` lambda.
    /// When `week` is nil the backend resolves the just-completed week
    /// from Sleeper's `nfl_state.week - 1`; the JSON key is omitted from
    /// the wire payload (not sent as `null`) so the backend's default
    /// kicks in cleanly.
    ///
    /// Backend route is `/admin/ai-review-weekly-trigger`, registered in
    /// F3's infra PR.
    func triggerWeeklyAIReview(
        week: Int?,
        dryRun: Bool,
        force: Bool
    ) async throws -> AIReviewTriggerResponse {
        let payload = WeeklyTriggerRequest(week: week, dryRun: dryRun, force: force)
        return try await postEncodableDecoding(
            "/admin/ai-review-weekly-trigger",
            body: payload
        )
    }

    // MARK: - Admin Report Flags (F3)

    /// Admin-only: toggle `is_redacted` or `do_not_broadcast` on a
    /// single report row. Backend path is `/admin/reports-flag` —
    /// flat (not nested under report id) so the same handler can
    /// service any of the three report types without re-routing.
    ///
    /// Returns the full updated metadata map so callers can mutate
    /// the local cached `AIReport` in place without a follow-up
    /// `/ai-reports/latest` round-trip.
    func setReportFlag(
        leagueId: String,
        reportType: AIReportType,
        period: String,
        flag: ReportFlag,
        value: Bool
    ) async throws -> ReportFlagResponse {
        let body: [String: Any] = [
            "league_id": leagueId,
            "report_type": reportType.rawValue,
            "period": period,
            "flag": flag.rawValue,
            "value": value,
        ]
        return try await postDecoding("/admin/reports-flag", body: body)
    }

    // MARK: - Admin Tables + Audit (F4)

    /// Admin-only: list every row of `whitelisted_users`. Returns the
    /// rich shape needed by the Users editor (`is_admin`, `is_active`,
    /// etc.) — separate from F1's `/admin/email-test-recipients`
    /// which trims columns for the email picker.
    func fetchWhitelistedUsers() async throws -> [WhitelistedUser] {
        let response: UsersListResponse = try await get(
            "/admin/users-list",
            queryItems: []
        )
        return response.users
    }

    /// Admin-only: update a single `whitelisted_users` row. Backend
    /// enforces a field allowlist (`email`, `display_name`, `is_admin`,
    /// `is_active`) and writes one `admin_audit` row per call. iOS
    /// passes only the fields the admin actually changed (`fields`).
    func updateWhitelistedUser(
        userId: String,
        fields: [String: AdminFieldValue]
    ) async throws -> UserUpdateResponse {
        var jsonFields: [String: Any] = [:]
        for (key, value) in fields {
            jsonFields[key] = value.jsonValue
        }
        let body: [String: Any] = [
            "user_id": userId,
            "fields": jsonFields,
        ]
        return try await postDecoding("/admin/users-update", body: body)
    }

    /// Admin-only: list every row of `whitelisted_leagues`. Same call
    /// pattern as `fetchWhitelistedUsers`. Method-name prefixed
    /// `Admin` so we don't collide with `LeagueStore`'s public-read
    /// Supabase call which is single-row + active-only.
    func fetchAdminWhitelistedLeagues() async throws -> [WhitelistedLeague] {
        let response: AdminLeaguesListResponse = try await get(
            "/admin/leagues-list",
            queryItems: []
        )
        return response.leagues
    }

    /// Admin-only: update a single `whitelisted_leagues` row. Backend
    /// enforces the allowlist (`league_name`, `is_active`,
    /// `is_dynasty`, `has_taxi`) and writes one `admin_audit` row.
    func updateWhitelistedLeague(
        leagueId: String,
        fields: [String: AdminFieldValue]
    ) async throws -> LeagueUpdateResponse {
        var jsonFields: [String: Any] = [:]
        for (key, value) in fields {
            jsonFields[key] = value.jsonValue
        }
        let body: [String: Any] = [
            "league_id": leagueId,
            "fields": jsonFields,
        ]
        return try await postDecoding("/admin/leagues-update", body: body)
    }

    /// Admin-only: paginated audit feed from `admin_audit`. Cursor is
    /// the opaque token returned by the previous page's `next_cursor`.
    /// When the Supabase table hasn't been provisioned yet, backend
    /// returns `tableMissing: true` and an empty row list — iOS
    /// renders a friendly explanatory empty state in that case.
    func fetchAuditEntries(
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> AuditListResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await get("/admin/audit-list", queryItems: items)
    }

    // MARK: - Private

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { throw XomperAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw XomperAPIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw XomperAPIError.httpError(statusCode: code)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XomperAPIError.encodingError(error)
        }
    }

    /// POST a typed `Encodable` body and decode the JSON response.
    /// Used for payloads where optional keys must be omitted entirely
    /// (via `encodeIfPresent`) rather than emitted as `null` — which
    /// `JSONSerialization` from `[String: Any]` cannot express.
    private func postEncodableDecoding<B: Encodable, T: Decodable>(
        _ path: String,
        body: B
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw XomperAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw XomperAPIError.encodingError(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw XomperAPIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw XomperAPIError.httpError(statusCode: code)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XomperAPIError.encodingError(error)
        }
    }

    private func postDecoding<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw XomperAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw XomperAPIError.encodingError(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw XomperAPIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw XomperAPIError.httpError(statusCode: code)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XomperAPIError.encodingError(error)
        }
    }

    private func post(_ path: String, body: [String: Any]) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw XomperAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw XomperAPIError.encodingError(error)
        }

        let (_,  response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw XomperAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw XomperAPIError.httpError(statusCode: code)
        }
    }
}
