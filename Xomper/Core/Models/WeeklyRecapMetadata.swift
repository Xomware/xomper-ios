import Foundation

// MARK: - Weekly Recap Metadata

/// Typed view of the `metadata` blob on a `weekly` AI report. Decoded
/// from `AIReport.metadataRawJSON` via `AIReport.decodeMetadata(_:)`.
///
/// The backend writes the full week recap to `body_markdown` AND a
/// per-matchup blurb array to `metadata.matchups[]` so the iOS layer
/// can render individual blurbs inline under each `MatchupCardView`.
///
/// Wire shape (snake_case):
/// ```json
/// {
///   "matchups": [
///     {
///       "matchup_id": 1,
///       "team_a": "Brock Party",
///       "team_b": "Gangsters of Love",
///       "handle_a": "domgiordano",
///       "handle_b": "ozz",
///       "user_id_a": "...", "user_id_b": "...",
///       "score_a": "198.6" | 198.6,
///       "score_b": "92.1"  | 92.1,
///       "margin":  "106.5" | 106.5,
///       "winner":  "a" | "b" | "tie",
///       "blurb":   "**Brock Party obliterated …**"
///     },
///     ...
///   ]
/// }
/// ```
struct WeeklyRecapMetadata: Decodable, Sendable, Hashable {
    let matchups: [WeeklyMatchupBlurb]

    enum CodingKeys: String, CodingKey {
        case matchups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.matchups = (try? c.decode([WeeklyMatchupBlurb].self, forKey: .matchups)) ?? []
    }

    init(matchups: [WeeklyMatchupBlurb]) {
        self.matchups = matchups
    }
}

/// A single per-matchup blurb extracted from a weekly recap's
/// metadata. Rendered as a small markdown card under each matchup row
/// on `MatchupsView` when the user is viewing a past, scored week.
struct WeeklyMatchupBlurb: Decodable, Sendable, Hashable, Identifiable {
    let matchupId: Int
    let teamA: String
    let teamB: String
    let handleA: String
    let handleB: String
    let userIdA: String
    let userIdB: String
    /// Scores + margin land as `String` from boto3 to avoid the
    /// `Decimal`-as-`float` precision shuffle. Defensive: accept Int /
    /// Double too in case the backend ever flips them.
    let scoreA: Double
    let scoreB: Double
    let margin: Double
    /// `"a"` / `"b"` / `"tie"` — preserved as-is so the renderer can
    /// pick an accent color without round-tripping through an enum.
    let winner: String
    /// Markdown blurb (e.g. `"**Brock Party obliterated …**"`).
    /// Rendered via `AttributedString(markdown:)`.
    let blurb: String

    var id: Int { matchupId }

    enum CodingKeys: String, CodingKey {
        case matchupId = "matchup_id"
        case teamA = "team_a"
        case teamB = "team_b"
        case handleA = "handle_a"
        case handleB = "handle_b"
        case userIdA = "user_id_a"
        case userIdB = "user_id_b"
        case scoreA = "score_a"
        case scoreB = "score_b"
        case margin
        case winner
        case blurb
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.matchupId = MockDraftDecoding.intOrString(c, key: .matchupId) ?? 0
        self.teamA = (try? c.decode(String.self, forKey: .teamA)) ?? ""
        self.teamB = (try? c.decode(String.self, forKey: .teamB)) ?? ""
        self.handleA = (try? c.decode(String.self, forKey: .handleA)) ?? ""
        self.handleB = (try? c.decode(String.self, forKey: .handleB)) ?? ""
        self.userIdA = (try? c.decode(String.self, forKey: .userIdA)) ?? ""
        self.userIdB = (try? c.decode(String.self, forKey: .userIdB)) ?? ""
        self.scoreA = MockDraftDecoding.doubleOrString(c, key: .scoreA) ?? 0
        self.scoreB = MockDraftDecoding.doubleOrString(c, key: .scoreB) ?? 0
        self.margin = MockDraftDecoding.doubleOrString(c, key: .margin) ?? 0
        self.winner = (try? c.decode(String.self, forKey: .winner)) ?? "tie"
        self.blurb = (try? c.decode(String.self, forKey: .blurb)) ?? ""
    }

    init(
        matchupId: Int,
        teamA: String,
        teamB: String,
        handleA: String = "",
        handleB: String = "",
        userIdA: String = "",
        userIdB: String = "",
        scoreA: Double,
        scoreB: Double,
        margin: Double,
        winner: String,
        blurb: String
    ) {
        self.matchupId = matchupId
        self.teamA = teamA
        self.teamB = teamB
        self.handleA = handleA
        self.handleB = handleB
        self.userIdA = userIdA
        self.userIdB = userIdB
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.margin = margin
        self.winner = winner
        self.blurb = blurb
    }
}
