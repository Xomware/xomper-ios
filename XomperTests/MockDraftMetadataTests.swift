import XCTest
@testable import Xomper

/// Tests for `MockDraftMetadata` + `MockedPick` + `WeeklyMatchupBlurb`
/// decoders. The wire payloads serialize numeric fields as either
/// `Int` (clean Lambda-side floats) or `String` (boto3's
/// `Decimal`-as-`String` quirk). The decoders must accept either.
@MainActor
final class MockDraftMetadataTests: XCTestCase {

    // MARK: - MockDraftMetadata

    func testMockDraftMetadata_picksCountAsInt_decodes() throws {
        let json = """
        {
          "personality": "bpa",
          "draft_year": "2026",
          "mode": "pure",
          "picks_count": 60,
          "picks": []
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(MockDraftMetadata.self, from: json)

        XCTAssertEqual(metadata.personality, "bpa")
        XCTAssertEqual(metadata.draftYear, "2026")
        XCTAssertEqual(metadata.mode, "pure")
        XCTAssertEqual(metadata.picksCount, 60)
        XCTAssertTrue(metadata.picks.isEmpty)
    }

    func testMockDraftMetadata_picksCountAsString_decodes() throws {
        let json = """
        {
          "personality": "team-fit",
          "draft_year": "2026",
          "mode": "pure",
          "picks_count": "60",
          "picks": []
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(MockDraftMetadata.self, from: json)

        XCTAssertEqual(metadata.personality, "team-fit")
        XCTAssertEqual(metadata.picksCount, 60)
    }

    func testMockDraftMetadata_missingFields_defaultsSafely() throws {
        let json = "{}".data(using: .utf8)!

        let metadata = try JSONDecoder().decode(MockDraftMetadata.self, from: json)

        XCTAssertEqual(metadata.personality, "")
        XCTAssertEqual(metadata.draftYear, "")
        XCTAssertEqual(metadata.mode, "pure")
        XCTAssertEqual(metadata.picksCount, 0)
        XCTAssertTrue(metadata.picks.isEmpty)
    }

    // MARK: - MockedPick

    func testMockedPick_valueAsString_decodes() throws {
        // Matches the in-session backfill: `value` serialized as String
        // to avoid boto3 Decimal-as-float precision drift.
        let json = """
        {
          "pick_no": 1,
          "round": 1,
          "slot": 1,
          "user_id": "u1",
          "team": "Brock Party",
          "handle": "domgiordano",
          "player_id": "p1",
          "player_name": "Bijan Robinson",
          "position": "RB",
          "nfl_team": "ATL",
          "value": "98.5"
        }
        """.data(using: .utf8)!

        let pick = try JSONDecoder().decode(MockedPick.self, from: json)

        XCTAssertEqual(pick.pickNo, 1)
        XCTAssertEqual(pick.team, "Brock Party")
        XCTAssertEqual(pick.value, 98.5, accuracy: 0.001)
    }

    func testMockedPick_valueAsDouble_decodes() throws {
        let json = """
        {
          "pick_no": 12,
          "round": 1,
          "slot": 12,
          "user_id": "u12",
          "team": "Gangsters of Love",
          "handle": "ozz",
          "player_id": "p12",
          "player_name": "Saquon Barkley",
          "position": "RB",
          "nfl_team": "PHI",
          "value": 94.2
        }
        """.data(using: .utf8)!

        let pick = try JSONDecoder().decode(MockedPick.self, from: json)

        XCTAssertEqual(pick.pickNo, 12)
        XCTAssertEqual(pick.value, 94.2, accuracy: 0.001)
    }

    func testMockedPick_pickNoAsString_decodes() throws {
        // Defensive: boto3 sometimes stringifies *all* numerics. Make
        // sure `pick_no` is happy with that too.
        let json = """
        {
          "pick_no": "13",
          "round": "2",
          "slot": "12",
          "user_id": "u12",
          "team": "Gangsters of Love",
          "handle": "ozz",
          "player_id": "p13",
          "player_name": "Player X",
          "position": "WR",
          "nfl_team": "PHI",
          "value": "82.1"
        }
        """.data(using: .utf8)!

        let pick = try JSONDecoder().decode(MockedPick.self, from: json)

        XCTAssertEqual(pick.pickNo, 13)
        XCTAssertEqual(pick.round, 2)
        XCTAssertEqual(pick.slot, 12)
    }

    // MARK: - WeeklyMatchupBlurb

    func testWeeklyMatchupBlurb_scoresAsString_decodes() throws {
        let json = """
        {
          "matchup_id": 1,
          "team_a": "Brock Party",
          "team_b": "Gangsters of Love",
          "handle_a": "domgiordano",
          "handle_b": "ozz",
          "user_id_a": "uA",
          "user_id_b": "uB",
          "score_a": "198.6",
          "score_b": "92.1",
          "margin":  "106.5",
          "winner":  "a",
          "blurb":   "**Brock Party obliterated Gangsters of Love 198.6-92.1**"
        }
        """.data(using: .utf8)!

        let blurb = try JSONDecoder().decode(WeeklyMatchupBlurb.self, from: json)

        XCTAssertEqual(blurb.matchupId, 1)
        XCTAssertEqual(blurb.teamA, "Brock Party")
        XCTAssertEqual(blurb.teamB, "Gangsters of Love")
        XCTAssertEqual(blurb.scoreA, 198.6, accuracy: 0.001)
        XCTAssertEqual(blurb.scoreB, 92.1, accuracy: 0.001)
        XCTAssertEqual(blurb.margin, 106.5, accuracy: 0.001)
        XCTAssertEqual(blurb.winner, "a")
        XCTAssertTrue(blurb.blurb.contains("Brock Party obliterated"))
    }

    func testWeeklyMatchupBlurb_scoresAsDouble_decodes() throws {
        let json = """
        {
          "matchup_id": 2,
          "team_a": "Team X",
          "team_b": "Team Y",
          "handle_a": "x",
          "handle_b": "y",
          "user_id_a": "uX",
          "user_id_b": "uY",
          "score_a": 121.4,
          "score_b": 118.9,
          "margin":  2.5,
          "winner":  "a",
          "blurb":   "Squeaker."
        }
        """.data(using: .utf8)!

        let blurb = try JSONDecoder().decode(WeeklyMatchupBlurb.self, from: json)

        XCTAssertEqual(blurb.scoreA, 121.4, accuracy: 0.001)
        XCTAssertEqual(blurb.scoreB, 118.9, accuracy: 0.001)
        XCTAssertEqual(blurb.margin, 2.5, accuracy: 0.001)
    }

    func testWeeklyMatchupBlurb_missingOptionalFields_defaultsSafely() throws {
        // Minimum-viable blurb — only `matchup_id` + `blurb` present.
        let json = """
        {
          "matchup_id": 3,
          "blurb": "Some recap text."
        }
        """.data(using: .utf8)!

        let blurb = try JSONDecoder().decode(WeeklyMatchupBlurb.self, from: json)

        XCTAssertEqual(blurb.matchupId, 3)
        XCTAssertEqual(blurb.teamA, "")
        XCTAssertEqual(blurb.scoreA, 0)
        XCTAssertEqual(blurb.winner, "tie")
        XCTAssertEqual(blurb.blurb, "Some recap text.")
    }

    // MARK: - WeeklyRecapMetadata

    func testWeeklyRecapMetadata_decodesArrayOfBlurbs() throws {
        let json = """
        {
          "matchups": [
            {
              "matchup_id": 1,
              "team_a": "A", "team_b": "B",
              "handle_a": "a", "handle_b": "b",
              "user_id_a": "uA", "user_id_b": "uB",
              "score_a": "100.0", "score_b": "80.0", "margin": "20.0",
              "winner": "a", "blurb": "A win."
            },
            {
              "matchup_id": 2,
              "team_a": "C", "team_b": "D",
              "handle_a": "c", "handle_b": "d",
              "user_id_a": "uC", "user_id_b": "uD",
              "score_a": "90.0", "score_b": "95.0", "margin": "5.0",
              "winner": "b", "blurb": "D wins."
            }
          ]
        }
        """.data(using: .utf8)!

        let recap = try JSONDecoder().decode(WeeklyRecapMetadata.self, from: json)

        XCTAssertEqual(recap.matchups.count, 2)
        XCTAssertEqual(recap.matchups[0].teamA, "A")
        XCTAssertEqual(recap.matchups[1].winner, "b")
    }

    // MARK: - AIReport.decodeMetadata round-trip

    func testAIReport_decodeMetadata_extractsTypedMetadata() throws {
        // Mirrors the actual wire shape returned by the list endpoint:
        // the top-level `AIReport` JSON with `metadata` carrying a
        // nested map containing `picks[]`.
        let json = """
        {
          "pk": "LEAGUE#L1",
          "sk": "REPORT#mock#2026-bpa",
          "league_id": "L1",
          "report_type": "mock",
          "period": "2026-bpa",
          "body_markdown": "## Mock Draft\\nBPA",
          "metadata": {
            "personality": "bpa",
            "draft_year": "2026",
            "mode": "pure",
            "picks_count": "60",
            "picks": [
              {
                "pick_no": 1, "round": 1, "slot": 1,
                "user_id": "u1", "team": "Brock Party", "handle": "dom",
                "player_id": "p1", "player_name": "Bijan Robinson",
                "position": "RB", "nfl_team": "ATL",
                "value": "98.5"
              }
            ]
          },
          "created_at": "2026-04-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(AIReport.self, from: json)

        XCTAssertEqual(report.reportType, .mock)
        XCTAssertEqual(report.metadata["personality"], "bpa")
        XCTAssertEqual(report.metadata["picks_count"], "60")

        // Structured decode of the nested map.
        let typed = report.decodeMetadata(MockDraftMetadata.self)
        XCTAssertNotNil(typed)
        XCTAssertEqual(typed?.personality, "bpa")
        XCTAssertEqual(typed?.picksCount, 60)
        XCTAssertEqual(typed?.picks.count, 1)
        XCTAssertEqual(typed?.picks.first?.playerName, "Bijan Robinson")
    }

    // MARK: - AIReportType.mock case

    func testAIReportType_mockCase_decodes() throws {
        let json = "\"mock\"".data(using: .utf8)!
        let type = try JSONDecoder().decode(AIReportType.self, from: json)
        XCTAssertEqual(type, .mock)
        XCTAssertEqual(type.displayName, "Mock Draft")
    }

    // MARK: - AIReviewStore.weeklyPeriod helper

    func testWeeklyPeriod_padsWeekToTwoDigits() {
        XCTAssertEqual(AIReviewStore.weeklyPeriod(season: "2025", week: 4), "2025W04")
        XCTAssertEqual(AIReviewStore.weeklyPeriod(season: "2025", week: 12), "2025W12")
        XCTAssertEqual(AIReviewStore.weeklyPeriod(season: "2024", week: 1), "2024W01")
    }

    func testWeeklyPeriod_emptySeasonOrInvalidWeek_returnsEmpty() {
        XCTAssertEqual(AIReviewStore.weeklyPeriod(season: "", week: 4), "")
        XCTAssertEqual(AIReviewStore.weeklyPeriod(season: "2025", week: 0), "")
        XCTAssertEqual(AIReviewStore.weeklyPeriod(season: "2025", week: -1), "")
    }
}
