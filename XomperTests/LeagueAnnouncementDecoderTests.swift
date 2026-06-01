import XCTest
@testable import Xomper

/// Wire-decode tests for `LeagueAnnouncement`. Covers the public-read
/// shape from `/announcements` and the admin shape from
/// `/admin/announcements-list`. Backend serialises ISO8601 UTC strings
/// (with or without fractional seconds) for `expires_at`,
/// `created_at`, `updated_at` and emits `null` for missing expiries.
final class LeagueAnnouncementDecoderTests: XCTestCase {

    // MARK: - Happy path

    func test_decode_allFields() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "Draft is July 6",
          "body": "6:30pm ET sharp.",
          "priority": "critical",
          "expires_at": "2026-07-07T00:00:00Z",
          "is_active": true,
          "display_order": 0,
          "created_at": "2026-06-01T12:00:00Z",
          "updated_at": "2026-06-01T12:00:00Z"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(LeagueAnnouncement.self, from: data)

        XCTAssertEqual(decoded.id.uuidString.lowercased(), "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(decoded.title, "Draft is July 6")
        XCTAssertEqual(decoded.body, "6:30pm ET sharp.")
        XCTAssertEqual(decoded.priority, .critical)
        XCTAssertNotNil(decoded.expiresAt)
        XCTAssertTrue(decoded.isActive)
        XCTAssertEqual(decoded.displayOrder, 0)
        XCTAssertNotNil(decoded.createdAt)
        XCTAssertNotNil(decoded.updatedAt)
    }

    // MARK: - Null + missing fields

    func test_decode_nullExpiresAt() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "No expiry",
          "body": "Body",
          "priority": "info",
          "expires_at": null,
          "is_active": true,
          "display_order": 1
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(LeagueAnnouncement.self, from: data)

        XCTAssertNil(decoded.expiresAt)
        XCTAssertNil(decoded.createdAt)
        XCTAssertNil(decoded.updatedAt)
        XCTAssertEqual(decoded.priority, .info)
    }

    func test_decode_missingOptionalFields() throws {
        // Backend may omit display_order entirely when seeding. Decoder
        // should default to 0 + treat the row as active.
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "Minimal",
          "body": "Body",
          "priority": "info"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(LeagueAnnouncement.self, from: data)

        XCTAssertEqual(decoded.displayOrder, 0)
        XCTAssertTrue(decoded.isActive)
    }

    // MARK: - Priority enum resiliency

    func test_decode_unknownPriorityFallsBackToInfo() throws {
        // Defensive — if the backend adds a new priority before iOS
        // ships support, the decoder should default to `.info` rather
        // than throwing and blanking the card.
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "Future priority",
          "body": "Body",
          "priority": "URGENT",
          "is_active": true,
          "display_order": 0
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(LeagueAnnouncement.self, from: data)

        XCTAssertEqual(decoded.priority, .info)
    }

    func test_decode_acceptsFractionalSecondTimestamps() throws {
        // Postgres timestamptz can serialise with fractional seconds.
        // Decoder accepts both shapes.
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "Frac",
          "body": "Body",
          "priority": "info",
          "expires_at": "2026-07-07T12:34:56.789Z",
          "is_active": true,
          "display_order": 0
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(LeagueAnnouncement.self, from: data)

        XCTAssertNotNil(decoded.expiresAt)
    }

    // MARK: - List response

    func test_decode_publicListResponse() throws {
        let json = """
        {
          "Success": true,
          "count": 2,
          "rows": [
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "title": "A",
              "body": "Body A",
              "priority": "critical",
              "expires_at": null,
              "is_active": true,
              "display_order": 0
            },
            {
              "id": "66666666-7777-8888-9999-aaaaaaaaaaaa",
              "title": "B",
              "body": "Body B",
              "priority": "info",
              "expires_at": null,
              "is_active": true,
              "display_order": 1
            }
          ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AnnouncementsListResponse.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.rows.count, 2)
        XCTAssertEqual(response.rows.first?.priority, .critical)
    }

    func test_decode_adminListWithTableMissing() throws {
        let json = """
        {
          "Success": true,
          "count": 0,
          "rows": [],
          "table_missing": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(AdminAnnouncementsListResponse.self, from: data)

        XCTAssertTrue(response.tableMissing)
        XCTAssertTrue(response.rows.isEmpty)
    }
}
