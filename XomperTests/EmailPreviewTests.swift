import XCTest
@testable import Xomper

/// Decoder coverage for the new `EmailPreview` wire shape returned by
/// the three AI Review dry-run trigger endpoints. The struct ships in
/// F2 — see `docs/features/admin-portal/f2-preview/PLAN.md`.
final class EmailPreviewTests: XCTestCase {

    // MARK: - Happy path

    func testDecode_mapsSnakeCaseKeys() throws {
        let json = """
        {
          "recipient_user_id": "U123",
          "recipient_email": "adam@example.com",
          "display_name": "Adam",
          "subject": "Week 4 Recap",
          "text_body": "Adam,\\n\\nNice win.",
          "html_body_excerpt": "<html>hi</html>"
        }
        """

        let preview = try JSONDecoder().decode(
            EmailPreview.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(preview.recipientUserId, "U123")
        XCTAssertEqual(preview.recipientEmail, "adam@example.com")
        XCTAssertEqual(preview.displayName, "Adam")
        XCTAssertEqual(preview.subject, "Week 4 Recap")
        XCTAssertEqual(preview.textBody, "Adam,\n\nNice win.")
        XCTAssertEqual(preview.htmlBodyExcerpt, "<html>hi</html>")
    }

    /// `id` is derived from `recipientUserId` so `ForEach` /
    /// `.sheet(item:)` can use the struct directly without an
    /// auxiliary identifier.
    func testIdentifiable_idEqualsRecipientUserId() throws {
        let json = """
        {
          "recipient_user_id": "ABC",
          "recipient_email": "x@y.com",
          "display_name": "X",
          "subject": "s",
          "text_body": "t",
          "html_body_excerpt": ""
        }
        """
        let preview = try JSONDecoder().decode(
            EmailPreview.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(preview.id, "ABC")
        XCTAssertEqual(preview.id, preview.recipientUserId)
    }

    /// All fields are required — a missing key should fail to decode.
    /// Locks the contract so the backend can't silently drop a field
    /// without the iOS tests flagging it.
    func testDecode_throwsOnMissingField() {
        let json = """
        {
          "recipient_user_id": "U123",
          "recipient_email": "adam@example.com",
          "display_name": "Adam",
          "subject": "Week 4 Recap"
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(EmailPreview.self, from: Data(json.utf8))
        )
    }

    // MARK: - Trigger response coupling

    /// `AIReviewTriggerResponse.previews` is the wire-level surface
    /// that carries the array on `dry_run=true` responses. This test
    /// asserts the optional decode picks up the array correctly.
    func testTriggerResponse_decodesPreviewsArray() throws {
        let json = """
        {
          "report_id": "L1|REPORT#postDraft#2026",
          "dry_run": true,
          "delivery_count": 1,
          "model": "claude-haiku-4-5",
          "token_usage": { "input_tokens": 100, "output_tokens": 50 },
          "previews": [
            {
              "recipient_user_id": "U1",
              "recipient_email": "a@x.com",
              "display_name": "Adam",
              "subject": "S1",
              "text_body": "B1",
              "html_body_excerpt": "H1"
            },
            {
              "recipient_user_id": "U2",
              "recipient_email": "b@x.com",
              "display_name": "Beth",
              "subject": "S2",
              "text_body": "B2",
              "html_body_excerpt": "H2"
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(
            AIReviewTriggerResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.previews?.count, 2)
        XCTAssertEqual(response.previews?.first?.displayName, "Adam")
        XCTAssertEqual(response.previews?.last?.displayName, "Beth")
    }

    /// Broadcast responses don't include `previews` — it must remain
    /// optional so existing decode paths (and the F1 broadcast surface)
    /// keep working unchanged.
    func testTriggerResponse_previewsOptional() throws {
        let json = """
        {
          "report_id": "L1|REPORT#postDraft#2026",
          "dry_run": false,
          "delivery_count": 12,
          "model": "claude-haiku-4-5",
          "token_usage": { "input_tokens": 100, "output_tokens": 50 }
        }
        """

        let response = try JSONDecoder().decode(
            AIReviewTriggerResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(response.previews)
    }
}
