import Foundation

/// One CloudWatch log event row surfaced by `GET /admin/logs-query`
/// (F5). The backend pre-redacts the message before returning
/// (emails → `***@***`, sleeper IDs → `[uid]`, Anthropic keys →
/// `[key]`) so iOS just renders what it gets.
///
/// Wire shape (snake_case from the backend):
/// ```json
/// {
///   "id":        "37498012345/abcd...",
///   "timestamp": "2026-05-27T01:23:45.123Z",
///   "level":     "ERROR" | "WARN" | "INFO" | null,
///   "message":   "..."
/// }
/// ```
///
/// `level` is `decodeIfPresent` + lowercased to match the
/// case-insensitive `LogLevel` raw values. Missing / unknown levels
/// decode as nil — the row renders a neutral gray chip in that case.
struct LogEvent: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let timestamp: Date
    let level: LogLevel?
    let message: String

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case level
        case message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.message = (try? c.decode(String.self, forKey: .message)) ?? ""

        // Timestamp — backend emits ISO-8601 with optional fractional
        // seconds. Fall back to epoch 0 so a malformed row doesn't
        // crash the entire page.
        let raw = (try? c.decode(String.self, forKey: .timestamp)) ?? ""
        self.timestamp = AIReport.parseISO(raw) ?? Date(timeIntervalSince1970: 0)

        // Level — case-insensitive. Backend may emit "ERROR" / "Warn"
        // / "info" depending on the lambda. Normalise before mapping.
        if let raw = try? c.decodeIfPresent(String.self, forKey: .level), !raw.isEmpty {
            self.level = LogLevel(rawValue: raw.lowercased())
        } else {
            self.level = nil
        }
    }

    /// Memberwise init for tests / previews.
    init(
        id: String,
        timestamp: Date,
        level: LogLevel?,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try c.encode(iso.string(from: timestamp), forKey: .timestamp)
        try c.encodeIfPresent(level?.rawValue, forKey: .level)
        try c.encode(message, forKey: .message)
    }
}
