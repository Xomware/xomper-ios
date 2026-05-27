import XCTest
@testable import Xomper

/// F3 — verifies the three metadata accessors added to `AIReport`
/// (`isRedacted`, `doNotBroadcast`, `broadcastAt`) read off the same
/// flat-map source of truth that `metadata` already exposes. Also
/// exercises `ReportFlag` raw values + `ReportFlagResponse` decoding
/// since the API client wires them together.
@MainActor
final class ReportFlagTests: XCTestCase {

    // MARK: - Fixture helper

    private func makeReport(metadata: [String: String]) -> AIReport {
        AIReport(
            id: "L1|REPORT#weekly#2026W04",
            leagueId: "L1",
            reportType: .weekly,
            period: "2026W04",
            bodyMarkdown: "## Week 4",
            metadata: metadata,
            createdAt: Date(timeIntervalSince1970: 0),
            model: "claude-haiku-4-5",
            promptVersion: "f0-2026-05-21"
        )
    }

    // MARK: - isRedacted

    func test_isRedacted_trueWhenMetadataString() {
        let report = makeReport(metadata: ["is_redacted": "true"])
        XCTAssertTrue(report.isRedacted)
    }

    func test_isRedacted_falseWhenAbsent() {
        let report = makeReport(metadata: [:])
        XCTAssertFalse(report.isRedacted)
    }

    func test_isRedacted_falseWhenExplicitlyFalse() {
        let report = makeReport(metadata: ["is_redacted": "false"])
        XCTAssertFalse(report.isRedacted)
    }

    // MARK: - doNotBroadcast

    func test_doNotBroadcast_trueWhenMetadataString() {
        let report = makeReport(metadata: ["do_not_broadcast": "true"])
        XCTAssertTrue(report.doNotBroadcast)
    }

    func test_doNotBroadcast_falseWhenAbsent() {
        let report = makeReport(metadata: [:])
        XCTAssertFalse(report.doNotBroadcast)
    }

    func test_flagsAreIndependent() {
        let redacted = makeReport(metadata: ["is_redacted": "true"])
        XCTAssertTrue(redacted.isRedacted)
        XCTAssertFalse(redacted.doNotBroadcast)

        let dnb = makeReport(metadata: ["do_not_broadcast": "true"])
        XCTAssertFalse(dnb.isRedacted)
        XCTAssertTrue(dnb.doNotBroadcast)
    }

    // MARK: - broadcastAt

    func test_broadcastAt_nilWhenAbsent() {
        let report = makeReport(metadata: [:])
        XCTAssertNil(report.broadcastAt)
    }

    func test_broadcastAt_parsesISO8601WithoutFractional() {
        let report = makeReport(metadata: ["broadcast_at": "2026-09-30T15:42:11Z"])
        XCTAssertNotNil(report.broadcastAt)
    }

    func test_broadcastAt_parsesISO8601WithFractional() {
        let report = makeReport(metadata: ["broadcast_at": "2026-09-30T15:42:11.123Z"])
        XCTAssertNotNil(report.broadcastAt)
    }

    func test_broadcastAt_nilOnInvalidString() {
        let report = makeReport(metadata: ["broadcast_at": "not-a-date"])
        XCTAssertNil(report.broadcastAt)
    }

    // MARK: - ReportFlag wire values

    func test_reportFlag_rawValuesMatchBackend() {
        XCTAssertEqual(ReportFlag.isRedacted.rawValue, "is_redacted")
        XCTAssertEqual(ReportFlag.doNotBroadcast.rawValue, "do_not_broadcast")
    }

    func test_reportFlag_decodesFromRawString() throws {
        let json = "\"do_not_broadcast\""
        let decoded = try JSONDecoder().decode(
            ReportFlag.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded, .doNotBroadcast)
    }

    // MARK: - ReportFlagResponse decoding

    func test_reportFlagResponse_decodesFullPayload() throws {
        let json = """
        {
          "Success": true,
          "league_id": "L1",
          "report_type": "weekly",
          "period": "2026W04",
          "flag": "is_redacted",
          "value": true,
          "metadata": {
            "is_redacted": "true",
            "broadcast_at": "2026-09-30T15:42:11Z"
          }
        }
        """
        let response = try JSONDecoder().decode(
            ReportFlagResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.leagueId, "L1")
        XCTAssertEqual(response.reportType, "weekly")
        XCTAssertEqual(response.period, "2026W04")
        XCTAssertEqual(response.flag, "is_redacted")
        XCTAssertTrue(response.value)
        XCTAssertEqual(response.metadata["is_redacted"], "true")
        XCTAssertEqual(response.metadata["broadcast_at"], "2026-09-30T15:42:11Z")
    }
}
