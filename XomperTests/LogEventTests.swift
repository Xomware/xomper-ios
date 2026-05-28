import XCTest
@testable import Xomper

/// F5 — verifies `LogEvent` decodes the wire shape returned by
/// `GET /admin/logs-query` and that `LogsQueryResponse` handles the
/// happy path + null next_token + missing level cases.
@MainActor
final class LogEventTests: XCTestCase {

    // MARK: - Happy path

    func test_logEvent_decodesFullPayload() throws {
        let json = """
        {
            "id": "37498012345/abcd",
            "timestamp": "2026-05-27T01:23:45.123Z",
            "level": "ERROR",
            "message": "Traceback (most recent call last): ValueError"
        }
        """
        let event = try JSONDecoder().decode(LogEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.id, "37498012345/abcd")
        XCTAssertEqual(event.level, .error)
        XCTAssertEqual(event.message, "Traceback (most recent call last): ValueError")
        XCTAssertNotEqual(event.timestamp, Date(timeIntervalSince1970: 0),
                          "ISO timestamp should parse into a real date.")
    }

    func test_logEvent_decodesLowercaseLevel() throws {
        let json = """
        {
            "id": "1",
            "timestamp": "2026-05-27T01:23:45Z",
            "level": "warn",
            "message": "Cache miss"
        }
        """
        let event = try JSONDecoder().decode(LogEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.level, .warn)
    }

    func test_logEvent_decodesMixedCaseLevel() throws {
        let json = """
        {
            "id": "1",
            "timestamp": "2026-05-27T01:23:45Z",
            "level": "Info",
            "message": "Booted"
        }
        """
        let event = try JSONDecoder().decode(LogEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.level, .info)
    }

    // MARK: - Missing / null level

    func test_logEvent_missingLevelDecodesAsNil() throws {
        let json = """
        {
            "id": "1",
            "timestamp": "2026-05-27T01:23:45Z",
            "message": "Unstructured stdout line"
        }
        """
        let event = try JSONDecoder().decode(LogEvent.self, from: Data(json.utf8))
        XCTAssertNil(event.level)
        XCTAssertEqual(event.message, "Unstructured stdout line")
    }

    func test_logEvent_nullLevelDecodesAsNil() throws {
        let json = """
        {
            "id": "1",
            "timestamp": "2026-05-27T01:23:45Z",
            "level": null,
            "message": "msg"
        }
        """
        let event = try JSONDecoder().decode(LogEvent.self, from: Data(json.utf8))
        XCTAssertNil(event.level)
    }

    func test_logEvent_unknownLevelDecodesAsNil() throws {
        let json = """
        {
            "id": "1",
            "timestamp": "2026-05-27T01:23:45Z",
            "level": "FATAL",
            "message": "msg"
        }
        """
        let event = try JSONDecoder().decode(LogEvent.self, from: Data(json.utf8))
        XCTAssertNil(event.level, "Unknown levels should decode as nil rather than crash.")
    }

    // MARK: - LogsQueryResponse

    func test_logsQueryResponse_decodesHappyPath() throws {
        let json = """
        {
            "Success": true,
            "log_group": "ai-review-weekly",
            "events": [
                {
                    "id": "1",
                    "timestamp": "2026-05-27T01:23:45Z",
                    "level": "ERROR",
                    "message": "boom"
                },
                {
                    "id": "2",
                    "timestamp": "2026-05-27T01:23:46Z",
                    "level": null,
                    "message": "untagged"
                }
            ],
            "next_token": "abc123"
        }
        """
        let response = try JSONDecoder().decode(
            LogsQueryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.logGroup, "ai-review-weekly")
        XCTAssertEqual(response.events.count, 2)
        XCTAssertEqual(response.events[0].level, .error)
        XCTAssertNil(response.events[1].level)
        XCTAssertEqual(response.nextToken, "abc123")
    }

    func test_logsQueryResponse_nullNextTokenDecodesAsNil() throws {
        let json = """
        {
            "Success": true,
            "log_group": "email-test",
            "events": [],
            "next_token": null
        }
        """
        let response = try JSONDecoder().decode(
            LogsQueryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(response.nextToken)
        XCTAssertTrue(response.events.isEmpty)
    }

    func test_logsQueryResponse_missingNextTokenDecodesAsNil() throws {
        let json = """
        {
            "Success": true,
            "log_group": "email-test",
            "events": []
        }
        """
        let response = try JSONDecoder().decode(
            LogsQueryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(response.nextToken)
    }

    // MARK: - LogGroup display names

    func test_logGroup_displayNamesPinned() {
        XCTAssertEqual(LogGroup.aiReviewWeekly.displayName, "Weekly AI Review (admin trigger)")
        XCTAssertEqual(LogGroup.weeklyRecap.displayName, "Weekly Recap (legacy)")
        XCTAssertEqual(LogGroup.emailTest.displayName, "Test Email")
        XCTAssertEqual(LogGroup.allCases.count, 10, "Allowlist must have exactly 10 entries.")
    }

    // MARK: - LogLevel mapping

    func test_logLevel_rawValueIsLowercased() {
        XCTAssertEqual(LogLevel.info.rawValue, "info")
        XCTAssertEqual(LogLevel.warn.rawValue, "warn")
        XCTAssertEqual(LogLevel.error.rawValue, "error")
    }
}
