import SwiftUI

/// One LLM-generated league report.
///
/// Backed by the `xomper-ai-reports` DynamoDB table — see F0 plan
/// `docs/features/ai-review/f0-shared-infra/PLAN.md`. The same struct
/// covers the three report types (post-draft, preseason, weekly) so a
/// single archive list + single detail view can render all of them.
///
/// JSON shape (snake_case from the backend):
/// ```json
/// {
///   "pk": "LEAGUE#<league_id>",
///   "sk": "REPORT#weekly#2026W04",
///   "league_id": "1181789700187090944",
///   "report_type": "weekly",
///   "period": "2026W04",
///   "body_markdown": "## Week 4 …",
///   "metadata": { "model": "...", "token_usage_in": 1234, ... },
///   "created_at": "2026-09-30T15:42:11Z",
///   "model": "claude-haiku-4-5",
///   "prompt_version": "f0-2026-05-21"
/// }
/// ```
struct AIReport: Decodable, Identifiable, Sendable, Hashable {
    /// Composite ID. Derived from `pk + sk` so the struct is stable
    /// across decodings. Not part of the wire payload.
    let id: String
    let leagueId: String
    let reportType: AIReportType
    let period: String
    let bodyMarkdown: String
    /// Raw JSON bytes of the `metadata` Dynamo Map, captured at decode
    /// time. Single source of truth for metadata — typed extractors
    /// (`decodeMetadata(_:)`) read nested structures (`picks[]`,
    /// `matchups[]`) here, and the `metadata` computed property
    /// surfaces top-level scalar keys lazily for call sites like
    /// `metadata["dry_run"]`.
    let metadataRawJSON: Data?

    /// Flat string→string view of the metadata blob's top-level scalar
    /// keys. Derived lazily from `metadataRawJSON` so there is only
    /// one source of truth — no risk of the two diverging. Nested
    /// values (arrays, objects) are not surfaced here; use
    /// `decodeMetadata(_:)` to read those.
    var metadata: [String: String] {
        guard let data = metadataRawJSON else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in json {
            if let s = v as? String { out[k] = s }
            else if let b = v as? Bool { out[k] = b ? "true" : "false" }
            else if let n = v as? NSNumber { out[k] = n.stringValue }
        }
        return out
    }
    let createdAt: Date
    let model: String?
    let promptVersion: String?

    enum CodingKeys: String, CodingKey {
        case pk, sk
        case leagueId = "league_id"
        case reportType = "report_type"
        case period
        case bodyMarkdown = "body_markdown"
        case metadata
        case createdAt = "created_at"
        case model
        case promptVersion = "prompt_version"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pk = (try? c.decode(String.self, forKey: .pk)) ?? ""
        let sk = (try? c.decode(String.self, forKey: .sk)) ?? ""
        self.id = "\(pk)|\(sk)"
        self.leagueId = (try? c.decode(String.self, forKey: .leagueId)) ?? ""
        let rawType = (try? c.decode(String.self, forKey: .reportType)) ?? "weekly"
        self.reportType = AIReportType(rawValue: rawType) ?? .weekly
        self.period = (try? c.decode(String.self, forKey: .period)) ?? ""
        self.bodyMarkdown = (try? c.decode(String.self, forKey: .bodyMarkdown)) ?? ""

        // Metadata is a Dynamo Map of mixed scalars + nested
        // structures. We decode it once as `JSONValue` (full JSON
        // grammar) and re-encode to raw bytes — that single blob is
        // then the source for both nested typed decode
        // (`decodeMetadata(_:)`) and the flat `metadata` computed
        // accessor for scalar reads.
        if let rawValue = try? c.decode(JSONValue.self, forKey: .metadata) {
            self.metadataRawJSON = try? JSONEncoder().encode(rawValue)
        } else {
            self.metadataRawJSON = nil
        }

        // ISO 8601 with optional fractional seconds.
        let createdRaw = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        self.createdAt = AIReport.parseISO(createdRaw) ?? Date(timeIntervalSince1970: 0)

        self.model = try? c.decodeIfPresent(String.self, forKey: .model)
        self.promptVersion = try? c.decodeIfPresent(String.self, forKey: .promptVersion)
    }

    /// Memberwise init for tests / previews. Not used by the decoder.
    /// Pass either `metadata` (a flat string map — convenient for tests)
    /// OR `metadataRawJSON` (raw bytes, supports nested structures). If
    /// `metadataRawJSON` is provided, it wins. If only `metadata` is
    /// provided, it's serialized to JSON bytes so the computed
    /// `metadata` accessor returns the same map round-trip.
    init(
        id: String,
        leagueId: String,
        reportType: AIReportType,
        period: String,
        bodyMarkdown: String,
        metadata: [String: String] = [:],
        metadataRawJSON: Data? = nil,
        createdAt: Date,
        model: String? = nil,
        promptVersion: String? = nil
    ) {
        self.id = id
        self.leagueId = leagueId
        self.reportType = reportType
        self.period = period
        self.bodyMarkdown = bodyMarkdown
        if let metadataRawJSON {
            self.metadataRawJSON = metadataRawJSON
        } else if metadata.isEmpty {
            self.metadataRawJSON = nil
        } else {
            self.metadataRawJSON = try? JSONSerialization.data(withJSONObject: metadata)
        }
        self.createdAt = createdAt
        self.model = model
        self.promptVersion = promptVersion
    }

    /// Decode the structured metadata blob into a strongly-typed
    /// Swift model — used by mock drafts (`MockDraftMetadata`) and
    /// weekly recaps (`WeeklyRecapMetadata`) that need the nested
    /// `picks[]` / `matchups[]` arrays the flat string map throws
    /// away. Returns `nil` when the raw JSON is missing or the shape
    /// doesn't match — callers fall back to an empty state.
    func decodeMetadata<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = metadataRawJSON else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Human-friendly title for cards and detail headers.
    /// e.g. "Post-Draft Recap — 2026" / "Week 4 Recap — 2026W04".
    var displayTitle: String {
        "\(reportType.displayName) — \(period)"
    }

    // MARK: - F3 Metadata flags

    /// True when the admin has marked the report `is_redacted=true`
    /// in the metadata blob. Non-admin clients are filtered server-
    /// side; this accessor exists so admin surfaces can render the
    /// "REDACTED" badge and gate context-menu actions when the
    /// `showRedacted` toggle on `AIReviewStore` is on.
    var isRedacted: Bool {
        metadata["is_redacted"] == "true"
    }

    /// True when the admin has marked the report `do_not_broadcast=true`.
    /// Pre-broadcast lock — the backend re-reads metadata immediately
    /// before SES fan-out and aborts with 409 when this is set. iOS
    /// surfaces this on the preview view's Broadcast button so the
    /// admin sees the lock before attempting the round-trip.
    var doNotBroadcast: Bool {
        metadata["do_not_broadcast"] == "true"
    }

    /// When the report was last broadcast to all whitelisted users.
    /// Stamped by the backend immediately AFTER successful SES fan-out
    /// (postdraft / preseason / weekly all share the same helper).
    /// `nil` for dry-run-only reports or before the first broadcast.
    var broadcastAt: Date? {
        guard let raw = metadata["broadcast_at"] else { return nil }
        return AIReport.parseISO(raw)
    }

    /// First ~80 chars of the markdown body, stripped of leading
    /// markdown markers. Used by the archive list + Home card.
    var previewSnippet: String {
        let lines = bodyMarkdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }
        // Skip leading headings — prefer the first paragraph.
        let firstParagraph = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") })
            ?? lines.first
            ?? ""
        let stripped = firstParagraph
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
        if stripped.count <= 120 { return stripped }
        let idx = stripped.index(stripped.startIndex, offsetBy: 120)
        return String(stripped[..<idx]) + "…"
    }

    static func parseISO(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

/// One of the three AI report flavors the backend produces. The raw
/// values mirror what `report_type` carries in DynamoDB / the API.
///
/// Backend enforces camelCase via `REPORT_TYPES = ("postDraft",
/// "preseason", "weekly", "mock")` in `lambdas/common/ai_reports_store.py`.
/// `preseason`, `weekly`, and `mock` already default to their case
/// names, but `postDraft` must be pinned to the camelCase wire value
/// (was `"post-draft"` in F0, which would fail to decode).
enum AIReportType: String, Codable, Sendable, CaseIterable, Hashable {
    case postDraft = "postDraft"
    case preseason = "preseason"
    case weekly = "weekly"
    case weekPreview = "weekPreview"
    case mock = "mock"

    /// Display name used in chips and titles.
    var displayName: String {
        switch self {
        case .postDraft:   "Post-Draft"
        case .preseason:   "Preseason"
        case .weekly:      "Weekly"
        case .weekPreview: "Week Preview"
        case .mock:        "Mock Draft"
        }
    }

    /// SF Symbol used as the chip glyph.
    var systemImage: String {
        switch self {
        case .postDraft:   "list.clipboard.fill"
        case .preseason:   "calendar"
        case .weekly:      "sparkles"
        case .weekPreview: "calendar.badge.clock"
        case .mock:        "wand.and.stars"
        }
    }

    /// Accent color used on the type chip. All three lean on the
    /// Midnight Emerald palette; championGold is the AI Review accent
    /// per the F0 plan.
    var accentColor: Color {
        switch self {
        case .postDraft:   XomperColors.championGold
        case .preseason:   XomperColors.successGreen
        case .weekly:      XomperColors.championGold
        case .weekPreview: XomperColors.errorRed
        case .mock:        XomperColors.championGold
        }
    }
}

// MARK: - Trigger Response

/// Response from `POST /admin/ai-review-postdraft-trigger`.
///
/// Backend returns the freshly-written `AIReport` row (so the iOS
/// admin card can immediately reflect the new state without a second
/// fetch) plus delivery counts and Anthropic token usage for the run.
///
/// Wire shape (snake_case):
/// ```json
/// {
///   "report_id": "LEAGUE#...|REPORT#postDraft#2026",
///   "dry_run": true,
///   "delivery_count": 1,
///   "model": "claude-haiku-4-5",
///   "token_usage": { "input_tokens": 1234, "output_tokens": 567 },
///   "report": { ...AIReport... },
///   "previews": [ ...EmailPreview... ]  // F2: only present on dry_run=true
/// }
/// ```
///
/// `previews` is populated by the dry-run path only — broadcast
/// (`dry_run=false`) responses leave it `nil`. See F2 plan for the
/// cap rules and ordering guarantees (`docs/features/admin-portal/
/// f2-preview/PLAN.md`).
struct AIReviewTriggerResponse: Decodable, Sendable {
    let reportId: String
    let dryRun: Bool
    let deliveryCount: Int
    let model: String
    let tokenUsage: TokenUsage?
    let report: AIReport?
    /// F2: rendered email previews, one per active whitelisted user.
    /// Server pre-sorts by `display_name`. `nil` when `dry_run=false`.
    let previews: [EmailPreview]?

    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case dryRun = "dry_run"
        case deliveryCount = "delivery_count"
        case model
        case tokenUsage = "token_usage"
        case report
        case previews
    }
}

/// Anthropic token usage for a single Claude call. All fields land
/// in the trigger response's `token_usage` blob; cache fields are
/// optional because non-cached calls won't include them.
struct TokenUsage: Decodable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

// MARK: - Helpers

/// Full JSON-grammar value used when round-tripping the `metadata`
/// blob through `JSONEncoder` so a typed decoder can later re-extract
/// nested arrays + objects (mock-draft `picks[]`, weekly
/// `matchups[]`). Flat scalar reads (`metadata["dry_run"]` in
/// AdminView, etc.) are surfaced via `AIReport.metadata`, a computed
/// accessor over the same source-of-truth raw bytes.
enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)    { self = .bool(v); return }
        if let v = try? c.decode(Int.self)     { self = .int(v); return }
        if let v = try? c.decode(Double.self)  { self = .double(v); return }
        if let v = try? c.decode(String.self)  { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .null:          try c.encodeNil()
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
