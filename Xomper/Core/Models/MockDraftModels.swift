import Foundation

// MARK: - Mock Draft Metadata

/// Typed view of the `metadata` blob on a `mock` AI report. Decoded
/// from `AIReport.metadataRawJSON` via `AIReport.decodeMetadata(_:)`.
///
/// Wire shape (snake_case):
/// ```json
/// {
///   "personality": "bpa" | "team-fit" | "wildcard",
///   "draft_year":  "2026",
///   "mode":        "pure",
///   "picks_count": "60" | 60,
///   "picks":       [ { ...MockedPick... }, ... ]
/// }
/// ```
///
/// Defensive against boto3/Dynamo quirks: numeric fields
/// (`picks_count` and `MockedPick.value` etc.) may arrive as either
/// `Int` or `String`. The custom inits handle both.
struct MockDraftMetadata: Decodable, Sendable, Hashable {
    let personality: String
    let draftYear: String
    let mode: String
    let picksCount: Int
    let picks: [MockedPick]

    enum CodingKeys: String, CodingKey {
        case personality
        case draftYear = "draft_year"
        case mode
        case picksCount = "picks_count"
        case picks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.personality = (try? c.decode(String.self, forKey: .personality)) ?? ""
        self.draftYear = (try? c.decode(String.self, forKey: .draftYear)) ?? ""
        self.mode = (try? c.decode(String.self, forKey: .mode)) ?? "pure"
        self.picksCount = MockDraftDecoding.intOrString(c, key: .picksCount) ?? 0
        self.picks = (try? c.decode([MockedPick].self, forKey: .picks)) ?? []
    }

    init(
        personality: String,
        draftYear: String,
        mode: String = "pure",
        picksCount: Int,
        picks: [MockedPick]
    ) {
        self.personality = personality
        self.draftYear = draftYear
        self.mode = mode
        self.picksCount = picksCount
        self.picks = picks
    }
}

/// A single pick from a mock draft. Built server-side by the
/// mock-draft engine — the iOS layer renders it as-is.
struct MockedPick: Decodable, Sendable, Hashable, Identifiable {
    let pickNo: Int
    let round: Int
    let slot: Int
    let userId: String
    let team: String
    let handle: String
    let playerId: String
    let playerName: String
    let position: String
    let nflTeam: String
    /// Mock-engine internal value score. Wire shape is `String` (boto3
    /// avoids float precision quirks by serializing as a string), but
    /// older snapshots may emit `Double` — both are accepted.
    let value: Double

    var id: Int { pickNo }

    enum CodingKeys: String, CodingKey {
        case pickNo = "pick_no"
        case round, slot
        case userId = "user_id"
        case team
        case handle
        case playerId = "player_id"
        case playerName = "player_name"
        case position
        case nflTeam = "nfl_team"
        case value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.pickNo   = MockDraftDecoding.intOrString(c, key: .pickNo) ?? 0
        self.round    = MockDraftDecoding.intOrString(c, key: .round) ?? 0
        self.slot     = MockDraftDecoding.intOrString(c, key: .slot) ?? 0
        self.userId     = (try? c.decode(String.self, forKey: .userId)) ?? ""
        self.team       = (try? c.decode(String.self, forKey: .team)) ?? ""
        self.handle     = (try? c.decode(String.self, forKey: .handle)) ?? ""
        self.playerId   = (try? c.decode(String.self, forKey: .playerId)) ?? ""
        self.playerName = (try? c.decode(String.self, forKey: .playerName)) ?? ""
        self.position   = (try? c.decode(String.self, forKey: .position)) ?? ""
        self.nflTeam    = (try? c.decode(String.self, forKey: .nflTeam)) ?? ""
        self.value      = MockDraftDecoding.doubleOrString(c, key: .value) ?? 0
    }

    init(
        pickNo: Int,
        round: Int,
        slot: Int,
        userId: String,
        team: String,
        handle: String,
        playerId: String,
        playerName: String,
        position: String,
        nflTeam: String,
        value: Double
    ) {
        self.pickNo = pickNo
        self.round = round
        self.slot = slot
        self.userId = userId
        self.team = team
        self.handle = handle
        self.playerId = playerId
        self.playerName = playerName
        self.position = position
        self.nflTeam = nflTeam
        self.value = value
    }
}

// MARK: - Personality Presentation

/// Static metadata used by `MocksView` to render a personality card
/// (display name, blurb, ordering). Keyed by the lowercase identifier
/// the backend stores in `metadata.personality`.
enum MockDraftPersonality: String, CaseIterable, Sendable {
    case bpa = "bpa"
    case teamFit = "team-fit"
    case wildcard = "wildcard"

    /// Stable display order — BPA first because it's the most
    /// conventional, wildcard last because it's the chaos take.
    static var displayOrder: [MockDraftPersonality] {
        [.bpa, .teamFit, .wildcard]
    }

    var displayName: String {
        switch self {
        case .bpa:      "Best Player Available"
        case .teamFit:  "Team Fit"
        case .wildcard: "Wildcard"
        }
    }

    var blurb: String {
        switch self {
        case .bpa:
            "Picks the highest-rated player on the board regardless of roster construction."
        case .teamFit:
            "Weights each team's positional needs against player value — closer to how real GMs draft."
        case .wildcard:
            "Random selection within the top 8 available — surfaces the chaotic alternate timelines."
        }
    }

    /// Match the personality identifier from a report's metadata. The
    /// backend emits the canonical lowercase form; this is a hook in
    /// case future runs add variants.
    static func from(_ raw: String) -> MockDraftPersonality? {
        MockDraftPersonality(rawValue: raw.lowercased())
    }
}

// MARK: - Decoding Helpers

/// Defensive numeric-field decoder shared between `MockDraftMetadata`,
/// `MockedPick`, and `WeeklyRecapMetadata`. Tries the native numeric
/// type first, then falls back to a string the backend may have
/// emitted via boto3's `Decimal`-as-string serialization quirk.
enum MockDraftDecoding {
    static func intOrString<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        key: K
    ) -> Int? {
        if let v = try? container.decode(Int.self, forKey: key) { return v }
        if let s = try? container.decode(String.self, forKey: key),
           let v = Int(s) {
            return v
        }
        if let d = try? container.decode(Double.self, forKey: key) {
            return Int(d)
        }
        return nil
    }

    static func doubleOrString<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        key: K
    ) -> Double? {
        if let v = try? container.decode(Double.self, forKey: key) { return v }
        if let v = try? container.decode(Int.self, forKey: key) {
            return Double(v)
        }
        if let s = try? container.decode(String.self, forKey: key),
           let v = Double(s) {
            return v
        }
        return nil
    }
}
