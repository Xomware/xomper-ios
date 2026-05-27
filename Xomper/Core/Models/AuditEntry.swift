import Foundation

/// One row from the Supabase `admin_audit` table — surfaced via
/// `GET /admin/audit-list` (F4). Every mutating admin lambda writes
/// one of these rows per call (`email.test` from F1, `reports.flag`
/// from F3, `users.update` + `leagues.update` from F4).
///
/// JSON shape (snake_case from the backend):
/// ```json
/// {
///   "id": "uuid",
///   "created_at": "2026-05-27T17:42:11.123Z",
///   "actor_user_id": "1234567890",
///   "action": "users.update",
///   "target_table": "whitelisted_users",
///   "target_id": "1234567890",
///   "before": { "is_admin": false },
///   "after": { "is_admin": true },
///   "metadata": {}
/// }
/// ```
///
/// `before` / `after` / `metadata` are stored as JSONB blobs on the
/// server side — arbitrary nested JSON. The iOS detail view renders
/// them via the shared `JSONValue` helper (`AIReport.swift`) so the
/// same code can walk a flag toggle, a user edit, or a future action
/// shape without bespoke decoders per action.
struct AuditEntry: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    let createdAt: Date
    let actorUserId: String
    let action: String
    let targetTable: String?
    let targetId: String?
    let before: JSONValue?
    let after: JSONValue?
    let metadata: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case actorUserId = "actor_user_id"
        case action
        case targetTable = "target_table"
        case targetId = "target_id"
        case before
        case after
        case metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.actorUserId = (try? c.decode(String.self, forKey: .actorUserId)) ?? ""
        self.action = (try? c.decode(String.self, forKey: .action)) ?? ""
        self.targetTable = try? c.decodeIfPresent(String.self, forKey: .targetTable)
        self.targetId = try? c.decodeIfPresent(String.self, forKey: .targetId)

        let createdRaw = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        self.createdAt = AIReport.parseISO(createdRaw) ?? Date(timeIntervalSince1970: 0)

        // before / after / metadata may be absent OR explicit JSON null.
        // Try decoding as JSONValue and treat .null as nil so the UI
        // doesn't render an empty "null" line per blob.
        if let beforeValue = try? c.decodeIfPresent(JSONValue.self, forKey: .before),
           case .null = beforeValue {
            self.before = nil
        } else {
            self.before = try? c.decodeIfPresent(JSONValue.self, forKey: .before)
        }

        if let afterValue = try? c.decodeIfPresent(JSONValue.self, forKey: .after),
           case .null = afterValue {
            self.after = nil
        } else {
            self.after = try? c.decodeIfPresent(JSONValue.self, forKey: .after)
        }

        if let metaValue = try? c.decodeIfPresent(JSONValue.self, forKey: .metadata),
           case .null = metaValue {
            self.metadata = nil
        } else {
            self.metadata = try? c.decodeIfPresent(JSONValue.self, forKey: .metadata)
        }
    }

    /// Memberwise init for tests / previews. Not used by the decoder.
    init(
        id: String,
        createdAt: Date,
        actorUserId: String,
        action: String,
        targetTable: String? = nil,
        targetId: String? = nil,
        before: JSONValue? = nil,
        after: JSONValue? = nil,
        metadata: JSONValue? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actorUserId = actorUserId
        self.action = action
        self.targetTable = targetTable
        self.targetId = targetId
        self.before = before
        self.after = after
        self.metadata = metadata
    }

    /// Human-friendly verb for the action. Falls back to the raw
    /// `action` string for unknown values so future audit actions
    /// don't crash the audit feed if iOS is behind backend.
    var actionDisplay: String {
        switch action {
        case "users.update":    return "Updated user"
        case "leagues.update":  return "Updated league"
        case "reports.flag":    return "Flagged report"
        case "email.test":      return "Sent test email"
        default:                return action
        }
    }

    /// SF Symbol for the action — drives the audit row's leading icon.
    var actionSymbol: String {
        switch action {
        case "users.update":    return "person.crop.circle.fill"
        case "leagues.update":  return "building.2.crop.circle.fill"
        case "reports.flag":    return "flag.fill"
        case "email.test":      return "paperplane.fill"
        default:                return "circle.dashed"
        }
    }
}

// MARK: - Pretty-print helper

extension JSONValue {
    /// Pretty-print this JSON value as a string. Used by `AuditDetailView`
    /// to render the before/after/metadata blobs in a monospaced block.
    /// Falls back to a single-line `String(describing:)` if encoding
    /// fails — non-fatal because the value is already in memory.
    var prettyPrintedString: String {
        guard let data = try? JSONEncoder.prettyPrintedEncoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: self)
        }
        return text
    }
}

extension JSONEncoder {
    /// Pretty-printed JSON encoder with sorted keys for stable ordering
    /// in the audit detail view. Stable ordering matters because admins
    /// reading a diff want fields in the same place across rows.
    static let prettyPrintedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
