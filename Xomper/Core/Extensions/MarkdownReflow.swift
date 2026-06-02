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

        // 1. Detach a leading title that's glued to the first sentence
        //    (e.g. "2025 Rookie Draft RecapThe 2025 class…").
        out = out.replacingOccurrences(
            of: #"(Recap|Standings|Summary|Review)([A-Z🏆🥇🥈🥉⚡️])"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )

        // 2. Pull every markdown heading onto its own line with
        //    blank-line padding. AI prompts now ask for ##/### per
        //    section but legacy stored content often jams the heading
        //    inline with the previous paragraph.
        out = out.replacingOccurrences(
            of: #"\s*(#{1,3}\s+[^\n]+)"#,
            with: "\n\n$1\n\n",
            options: .regularExpression
        )

        // 3. Break before any bold section header followed by an em-dash
        //    intro, e.g. "**ktatich (Kyle)** — Picks 1.02…".
        out = out.replacingOccurrences(
            of: #"(?<=[\.\!\?\)])\s*(\*\*[^*]+\*\*\s*—)"#,
            with: "\n\n$1",
            options: .regularExpression
        )

        // 4. Break before a NON-bold manager-style header pattern:
        //    "Week 4.cfolk (Connor Folk) — Picks 1.01" lacks bold but
        //    the `(<word>)\s*—\s*Picks?` shape is unambiguous.
        out = out.replacingOccurrences(
            of: #"(?<=[\.\!\?])([A-Za-z][A-Za-z0-9_]*\s*\([^)]+\)\s*—\s*Picks?\b)"#,
            with: "\n\n$1",
            options: .regularExpression
        )

        // 5. Break before "Round N" / "Week N" / "Final ... standings"
        //    when glued to a prior word.
        out = out.replacingOccurrences(
            of: #"(?<=[a-z\)\.])(\s*)((?:Round|Week)\s+\d+|Final[^.\n]{0,40}?standings)"#,
            with: "\n\n$2",
            options: .regularExpression
        )

        // 6. Break before "Game by Game" / "Around the League" /
        //    "Winner & Loser" / "Team-by-Team" / "Winners & Losers"
        //    section markers even without a heading hash, so weekly
        //    recaps that didn't emit a proper `##` still scan.
        out = out.replacingOccurrences(
            of: #"(?<=[a-z\)\.])(\s*)((?:Game by Game|Around the League|Winners? (?:& |and )Loser|Team-by-Team|Final 20\d\d standings)\b)"#,
            with: "\n\n$2",
            options: .regularExpression
        )

        // 7. Break before pick stems that hug prior text:
        //    "Connor's a hero.Pat Bryant 4.01" -> two paragraphs.
        out = out.replacingOccurrences(
            of: #"(?<=[\.\!\?])(?=[A-Z][a-zA-Z' ]+\s\d+\.\d{2}\b)"#,
            with: "\n\n",
            options: .regularExpression
        )

        // 8. Normalize whitespace — collapse 3+ newlines and strip
        //    leading whitespace on the result so SwiftUI's
        //    AttributedString(markdown:) sees clean input.
        out = out.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)

        return out
    }
}
