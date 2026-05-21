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

    // AI Review
    func fetchLatestAIReport(type: AIReportType) async throws -> AIReport?
    func fetchAIReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse
    func triggerPostDraftAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse
    func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse
    func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse
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
