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
    let metadata: [String: String]
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

        // Metadata is a Dynamo Map of mixed scalars. Decode leniently as
        // string→string so iOS doesn't need a full Any-codable layer.
        if let raw = try? c.decode([String: AnyScalar].self, forKey: .metadata) {
            var out: [String: String] = [:]
            for (k, v) in raw { out[k] = v.stringValue }
            self.metadata = out
        } else {
            self.metadata = [:]
        }

        // ISO 8601 with optional fractional seconds.
        let createdRaw = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        self.createdAt = AIReport.parseISO(createdRaw) ?? Date(timeIntervalSince1970: 0)

        self.model = try? c.decodeIfPresent(String.self, forKey: .model)
        self.promptVersion = try? c.decodeIfPresent(String.self, forKey: .promptVersion)
    }

    /// Memberwise init for tests / previews. Not used by the decoder.
    init(
        id: String,
        leagueId: String,
        reportType: AIReportType,
        period: String,
        bodyMarkdown: String,
        metadata: [String: String] = [:],
        createdAt: Date,
        model: String? = nil,
        promptVersion: String? = nil
    ) {
        self.id = id
        self.leagueId = leagueId
        self.reportType = reportType
        self.period = period
        self.bodyMarkdown = bodyMarkdown
        self.metadata = metadata
        self.createdAt = createdAt
        self.model = model
        self.promptVersion = promptVersion
    }

    /// Human-friendly title for cards and detail headers.
    /// e.g. "Post-Draft Recap — 2026" / "Week 4 Recap — 2026W04".
    var displayTitle: String {
        "\(reportType.displayName) — \(period)"
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

    private static func parseISO(_ raw: String) -> Date? {
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
/// "preseason", "weekly")` in `lambdas/common/ai_reports_store.py`.
/// `preseason` and `weekly` already default to their case names, but
/// `postDraft` must be pinned to the camelCase wire value (was
/// `"post-draft"` in F0, which would fail to decode).
enum AIReportType: String, Codable, Sendable, CaseIterable, Hashable {
    case postDraft = "postDraft"
    case preseason = "preseason"
    case weekly = "weekly"

    /// Display name used in chips and titles.
    var displayName: String {
        switch self {
        case .postDraft: "Post-Draft"
        case .preseason: "Preseason"
        case .weekly:    "Weekly"
        }
    }

    /// SF Symbol used as the chip glyph.
    var systemImage: String {
        switch self {
        case .postDraft: "list.clipboard.fill"
        case .preseason: "calendar"
        case .weekly:    "sparkles"
        }
    }

    /// Accent color used on the type chip. All three lean on the
    /// Midnight Emerald palette; championGold is the AI Review accent
    /// per the F0 plan.
    var accentColor: Color {
        switch self {
        case .postDraft: XomperColors.championGold
        case .preseason: XomperColors.successGreen
        case .weekly:    XomperColors.championGold
        }
    }
}

// MARK: - Helpers

/// Tiny shim that decodes a Dynamo Map attribute (JSON object of
/// mixed scalars) into something string-coercible. The Anthropic
/// metadata blob holds counts + names so this is sufficient — no
/// nested objects to traverse.
private enum AnyScalar: Decodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Int.self)    { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(Bool.self)   { self = .bool(v); return }
        self = .null
    }

    var stringValue: String {
        switch self {
        case .string(let s): s
        case .int(let i):    String(i)
        case .double(let d): String(d)
        case .bool(let b):   String(b)
        case .null:          ""
        }
    }
}
