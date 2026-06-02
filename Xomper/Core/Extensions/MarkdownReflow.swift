import Foundation

/// Lightweight markdown post-processor that injects paragraph breaks
/// into AI Review report bodies. Claude generates these recaps as one
/// long run with bold + em-dash markers but no `\n\n` between sections,
/// which renders as a wall of text. We can't re-flow at generation time
/// for content already in DynamoDB, and we want this to work uniformly
/// across postDraft / weekly / preseason — so we reflow at render time.
///
/// Rules applied in order, each idempotent:
/// 1. Insert `\n\n` before the AI's first body sentence when it
///    immediately follows the title (`...Recap**The 2025...` ->
///    `...Recap**\n\nThe 2025...`).
/// 2. Insert `\n\n` before per-team / per-section bold headers like
///    `**ktatich (Kyle)** —` and `**Round 2**` and `**Final standings:**`.
/// 3. Insert `\n\n` before headline patterns that hug a previous
///    sentence: `Round N`, `Week N`, `Final ... standings`, numbered
///    list-y stems (`1.01`, `2.07`) when glued to a prior word.
/// 4. Collapse 3+ consecutive newlines to exactly two so we don't
///    over-pad after multiple inserts.
enum MarkdownReflow {

    static func paragraphs(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }

        var out = raw

        // 1. Detach a leading title from the body. The AI emits a bold
        //    or plain header glued to the first sentence — e.g.
        //    "2025 Rookie Draft RecapThe 2025 class…" or
        //    "Week 17 Recap — 2025 — Championship + Final Standings🏆 CHAMPIONSHIP:…"
        //    Look for a transition from a "Recap"/"Standings"-y token
        //    directly into a capital letter or emoji.
        out = out.replacingOccurrences(
            of: #"(Recap|Standings|Summary)([A-Z🏆🥇🥈🥉⚡️])"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )

        // 2. Break before any bold section header followed by an em-dash
        //    intro, e.g. "**ktatich (Kyle)** — Picks 1.02…".
        //    Allow a leading period to absorb the previous sentence end.
        out = out.replacingOccurrences(
            of: #"(?<=[\.\!\?\)])\s*(\*\*[^*]+\*\*\s*—)"#,
            with: "\n\n$1",
            options: .regularExpression
        )

        // 3. Break before "Round N" / "Week N" / "Final ... standings"
        //    when glued to a prior word.
        out = out.replacingOccurrences(
            of: #"(?<=[a-z\)\.])(\s*)((?:Round|Week)\s+\d+|Final[^.\n]{0,40}?standings)"#,
            with: "\n\n$2",
            options: .regularExpression
        )

        // 4. Break before pick numbers that hug prior text:
        //    "Connor's a hero.Pat Bryant 4.01" -> two paragraphs.
        out = out.replacingOccurrences(
            of: #"(?<=[\.\!\?])(?=[A-Z][a-zA-Z' ]+\s\d+\.\d{2}\b)"#,
            with: "\n\n",
            options: .regularExpression
        )

        // 5. Normalize whitespace — collapse 3+ newlines and trim
        //    trailing whitespace on each line so SwiftUI's
        //    AttributedString(markdown:) sees clean input.
        out = out.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return out
    }
}
