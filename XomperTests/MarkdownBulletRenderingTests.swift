import XCTest
@testable import Xomper

/// Tests for the list-item handling added to the recap markdown
/// pipeline. Claude emits pick lines as single-newline "- " bullets;
/// before the fix `MarkdownBlockParser` collapsed a run of them into one
/// run-on paragraph ("...in Madden. - 1.02 name — ..."). These tests
/// pin the reflow → parse contract that turns them into discrete,
/// spaced `.bullet` blocks.
final class MarkdownBulletRenderingTests: XCTestCase {

    /// End-to-end: raw AI body with newline-led bullets reflows and
    /// parses into one bullet block per pick line.
    func testNewlineBullets_parseAsDiscreteBulletBlocks() {
        let raw = """
        Connor took the safe pick.
        - 1.02 reesegriffin — Caleb Williams (QB, CHI). Reese drafted his real team.
        - 1.03 mwynne16 — Josh Allen (QB, BUF). Solid.
        """

        let blocks = MarkdownBlockParser.parse(MarkdownReflow.paragraphs(raw))
        let bullets = blocks.filter { if case .bullet = $0 { return true } else { return false } }

        XCTAssertEqual(bullets.count, 2, "each '- ' line should become its own bullet")
        if case let .bullet(text) = bullets[0] {
            XCTAssertTrue(text.hasPrefix("1.02 reesegriffin"))
            XCTAssertFalse(text.contains(" - "), "bullet body must not swallow the next marker")
        } else {
            XCTFail("expected first bullet")
        }
    }

    /// A leading non-bullet sentence stays a paragraph; the bullets that
    /// follow do not get merged into it.
    func testLeadParagraphNotMergedIntoBullets() {
        let raw = "The room knew the math.\n- 1.01 cfolk — Patrick Mahomes (QB, KC). Safe."
        let blocks = MarkdownBlockParser.parse(MarkdownReflow.paragraphs(raw))

        guard case let .paragraph(p) = blocks.first else {
            return XCTFail("expected a lead paragraph block")
        }
        XCTAssertEqual(p, "The room knew the math.")
        XCTAssertFalse(p.contains("cfolk"), "the bullet must not fold into the lead paragraph")
    }

    /// `*` and `•` markers normalize to the same bullet treatment.
    func testAlternateBulletMarkers() {
        let raw = "Intro.\n* first item\n• second item"
        let blocks = MarkdownBlockParser.parse(MarkdownReflow.paragraphs(raw))
        let bullets = blocks.filter { if case .bullet = $0 { return true } else { return false } }
        XCTAssertEqual(bullets.count, 2)
    }
}
