import XCTest
@testable import Xomper

/// F4 — verifies `AuditEntry` decodes the wire shape returned by
/// `GET /admin/audit-list` and that the `actionDisplay` mapping
/// covers the four known mutating admin actions. Also exercises
/// the `AuditListResponse` decoder including the `table_missing`
/// signal the backend emits when the Supabase migration isn't
/// yet applied.
@MainActor
final class AuditEntryTests: XCTestCase {

    // MARK: - Full payload decode

    func test_auditEntry_decodesFullPayload() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "created_at": "2026-05-27T15:42:11.123Z",
            "actor_user_id": "12345",
            "action": "users.update",
            "target_table": "whitelisted_users",
            "target_id": "12345",
            "before": { "is_admin": false },
            "after": { "is_admin": true },
            "metadata": { "source": "ios" }
        }
        """
        let entry = try JSONDecoder().decode(
            AuditEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(entry.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(entry.actorUserId, "12345")
        XCTAssertEqual(entry.action, "users.update")
        XCTAssertEqual(entry.targetTable, "whitelisted_users")
        XCTAssertEqual(entry.targetId, "12345")
        XCTAssertNotNil(entry.before)
        XCTAssertNotNil(entry.after)
        XCTAssertNotNil(entry.metadata)
    }

    // MARK: - Optional fields tolerated

    func test_auditEntry_missingOptionalFields() throws {
        let json = """
        {
            "id": "abc",
            "created_at": "2026-05-27T15:42:11Z",
            "actor_user_id": "1",
            "action": "email.test"
        }
        """
        let entry = try JSONDecoder().decode(
            AuditEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(entry.id, "abc")
        XCTAssertEqual(entry.action, "email.test")
        XCTAssertNil(entry.targetTable)
        XCTAssertNil(entry.targetId)
        XCTAssertNil(entry.before)
        XCTAssertNil(entry.after)
        XCTAssertNil(entry.metadata)
    }

    // MARK: - JSON null on before/after

    func test_auditEntry_jsonNullBeforeDecodesAsNil() throws {
        let json = """
        {
            "id": "xyz",
            "created_at": "2026-05-27T15:42:11Z",
            "actor_user_id": "1",
            "action": "email.test",
            "before": null,
            "after": { "recipient_email": "test@example.com" }
        }
        """
        let entry = try JSONDecoder().decode(
            AuditEntry.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(entry.before, "JSON null for `before` should decode as nil, not as JSONValue.null.")
        XCTAssertNotNil(entry.after)
    }

    // MARK: - Nested JSONValue blobs

    func test_auditEntry_nestedJSONValueDecodes() throws {
        let json = """
        {
            "id": "x",
            "created_at": "2026-05-27T15:42:11Z",
            "actor_user_id": "1",
            "action": "leagues.update",
            "target_table": "whitelisted_leagues",
            "target_id": "L1",
            "before": {
                "is_dynasty": false,
                "divisions": 2,
                "tags": ["alpha", "beta"]
            },
            "after": {
                "is_dynasty": true,
                "divisions": 4,
                "tags": ["alpha", "beta", "gamma"]
            }
        }
        """
        let entry = try JSONDecoder().decode(
            AuditEntry.self,
            from: Data(json.utf8)
        )

        guard case .object(let before)? = entry.before else {
            XCTFail("Expected before to be a JSON object")
            return
        }
        XCTAssertEqual(before["is_dynasty"], .bool(false))
        XCTAssertEqual(before["divisions"], .int(2))

        guard case .object(let after)? = entry.after else {
            XCTFail("Expected after to be a JSON object")
            return
        }
        XCTAssertEqual(after["is_dynasty"], .bool(true))
        XCTAssertEqual(after["divisions"], .int(4))
    }

    // MARK: - actionDisplay mapping

    func test_actionDisplay_mapping() {
        let make = { (action: String) -> AuditEntry in
            AuditEntry(
                id: "x",
                createdAt: Date(),
                actorUserId: "1",
                action: action
            )
        }
        XCTAssertEqual(make("users.update").actionDisplay, "Updated user")
        XCTAssertEqual(make("leagues.update").actionDisplay, "Updated league")
        XCTAssertEqual(make("reports.flag").actionDisplay, "Flagged report")
        XCTAssertEqual(make("email.test").actionDisplay, "Sent test email")
        // Unknown action should pass through as-is.
        XCTAssertEqual(make("future.unknown").actionDisplay, "future.unknown")
    }

    func test_actionSymbol_mapping() {
        let make = { (action: String) -> AuditEntry in
            AuditEntry(
                id: "x",
                createdAt: Date(),
                actorUserId: "1",
                action: action
            )
        }
        XCTAssertEqual(make("users.update").actionSymbol, "person.crop.circle.fill")
        XCTAssertEqual(make("leagues.update").actionSymbol, "building.2.crop.circle.fill")
        XCTAssertEqual(make("reports.flag").actionSymbol, "flag.fill")
        XCTAssertEqual(make("email.test").actionSymbol, "paperplane.fill")
    }

    // MARK: - AuditListResponse decoding

    func test_auditListResponse_decodesFullPayload() throws {
        let json = """
        {
            "Success": true,
            "count": 1,
            "rows": [
                {
                    "id": "a",
                    "created_at": "2026-05-27T15:42:11Z",
                    "actor_user_id": "12345",
                    "action": "users.update"
                }
            ],
            "next_cursor": "cursor-abc"
        }
        """
        let response = try JSONDecoder().decode(
            AuditListResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.rows.count, 1)
        XCTAssertEqual(response.nextCursor, "cursor-abc")
        XCTAssertFalse(response.tableMissing)
    }

    func test_auditListResponse_tableMissingTrue() throws {
        let json = """
        {
            "Success": true,
            "count": 0,
            "rows": [],
            "table_missing": true
        }
        """
        let response = try JSONDecoder().decode(
            AuditListResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertTrue(response.tableMissing)
        XCTAssertEqual(response.rows.count, 0)
        XCTAssertNil(response.nextCursor)
    }

    func test_auditListResponse_tableMissingAbsentDefaultsFalse() throws {
        let json = """
        {
            "Success": true,
            "count": 0,
            "rows": []
        }
        """
        let response = try JSONDecoder().decode(
            AuditListResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertFalse(response.tableMissing)
    }

    // MARK: - WhitelistedLeague decoder

    func test_whitelistedLeague_decodesFullPayload() throws {
        let json = """
        {
            "id": "row-1",
            "league_id": "1181789700187090944",
            "league_name": "CLT Dynasty",
            "season": "2026",
            "is_active": true,
            "is_dynasty": true,
            "has_taxi": false,
            "divisions": 2,
            "size": 12
        }
        """
        let league = try JSONDecoder().decode(
            WhitelistedLeague.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(league.id, "row-1")
        XCTAssertEqual(league.leagueId, "1181789700187090944")
        XCTAssertEqual(league.leagueName, "CLT Dynasty")
        XCTAssertEqual(league.season, "2026")
        XCTAssertTrue(league.isActive)
        XCTAssertTrue(league.isDynasty)
        XCTAssertFalse(league.hasTaxi)
        XCTAssertEqual(league.divisions, 2)
        XCTAssertEqual(league.size, 12)
    }
}
