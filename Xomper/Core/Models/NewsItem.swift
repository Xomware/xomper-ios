import Foundation

/// One item in the league News feed — a completed Sleeper transaction
/// (trade / waiver / free-agent move) enriched with dynasty values, a
/// deterministic local write-up, and (for trades) a letter grade per side.
///
/// Pure value type. Built by `NewsBuilder.build(...)` from a raw
/// `Transaction` + the league's rosters/users + the player & value
/// stores. No LLM — every headline/summary/grade is derived locally so
/// the feed renders identically offline and in previews.
struct NewsItem: Identifiable, Sendable, Hashable {
    /// Sleeper `transaction_id`.
    let id: String
    let type: NewsType
    /// Scoring week the move was logged under (1...18).
    let week: Int
    let createdAt: Date
    /// Roster ids involved (2 for a trade, 1 for a move).
    let rosterIds: [Int]
    /// Per-roster acquired/relinquished breakdown. Two sides for a
    /// trade, one for a waiver/free-agent move.
    let sides: [NewsSide]
    /// Trade grade — nil for waiver/free-agent moves.
    let grade: TradeGrade?
    /// Short deterministic headline, e.g. "Dynasty Warriors ↔ Gridiron Kings".
    let headline: String
    /// Longer deterministic write-up describing the move + verdict.
    let summary: String

    /// True when `rosterId` is one of the teams in this item — drives the
    /// team filter.
    func involves(rosterId: Int) -> Bool {
        rosterIds.contains(rosterId)
    }
}

// MARK: - NewsType

enum NewsType: String, CaseIterable, Sendable, Hashable, Identifiable {
    case trade
    case waiver
    case freeAgent

    var id: String { rawValue }

    /// Map a raw Sleeper `transaction.type`. Returns nil for types we
    /// don't surface (e.g. "commissioner").
    init?(sleeperType: String?) {
        switch sleeperType {
        case "trade":       self = .trade
        case "waiver":      self = .waiver
        case "free_agent":  self = .freeAgent
        default:            return nil
        }
    }

    var label: String {
        switch self {
        case .trade:      "Trade"
        case .waiver:     "Waiver"
        case .freeAgent:  "Free Agent"
        }
    }

    var systemImage: String {
        switch self {
        case .trade:      "arrow.left.arrow.right"
        case .waiver:     "cart.fill"
        case .freeAgent:  "person.badge.plus"
        }
    }
}

// MARK: - NewsSide

/// One roster's involvement in a news item — what it acquired and what
/// it gave up, plus the summed dynasty value of each bucket.
struct NewsSide: Identifiable, Sendable, Hashable {
    let rosterId: Int
    let teamName: String
    let acquired: [NewsAsset]
    let relinquished: [NewsAsset]
    /// FAAB spent (waiver claim) or received/sent in a trade. nil when
    /// no budget changed hands.
    let faab: Int?

    var id: Int { rosterId }

    var acquiredValue: Int { acquired.reduce(0) { $0 + $1.value } }
    var relinquishedValue: Int { relinquished.reduce(0) { $0 + $1.value } }
    /// Net dynasty value swing for this roster (acquired − relinquished).
    var netValue: Int { acquiredValue - relinquishedValue }
}

// MARK: - NewsAsset

/// A single player or draft pick that changed hands.
struct NewsAsset: Identifiable, Sendable, Hashable {
    /// Sleeper player id, or a synthetic id for a pick.
    let id: String
    /// Display name — "Josh Allen" or "2026 1st".
    let name: String
    /// "QB"/"RB"/… for players, "PICK" for draft picks.
    let position: String
    /// Dynasty value. Picks are valued at the Mid tier per issue #145.
    let value: Int
    let isPick: Bool

    // MARK: - Pick Resolution (for used picks)

    /// For picks that have been used: the player who was drafted.
    /// nil for future picks or non-pick assets.
    let resolvedPlayerId: String?
    /// For picks that have been used: player name, e.g. "Caleb Williams".
    let resolvedPlayerName: String?
    /// For picks that have been used: player position, e.g. "QB".
    let resolvedPlayerPosition: String?

    init(
        id: String,
        name: String,
        position: String,
        value: Int,
        isPick: Bool,
        resolvedPlayerId: String? = nil,
        resolvedPlayerName: String? = nil,
        resolvedPlayerPosition: String? = nil
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.value = value
        self.isPick = isPick
        self.resolvedPlayerId = resolvedPlayerId
        self.resolvedPlayerName = resolvedPlayerName
        self.resolvedPlayerPosition = resolvedPlayerPosition
    }

    /// True if this was a pick that has since been used in a draft.
    var isResolvedPick: Bool {
        isPick && resolvedPlayerId != nil
    }
}

// MARK: - TradeGrade

/// Deterministic grade for a two-team trade. Each side earns a letter
/// from its share of the total dynasty value received; the differential
/// is the raw value gap between the two hauls.
struct TradeGrade: Sendable, Hashable {
    /// rosterId → letter grade for what that side received.
    let lettersByRoster: [Int: LetterGrade]
    /// Absolute dynasty-value gap between the two sides' hauls.
    let differential: Int
    /// |gap| / larger-side value (0...1).
    let percentGap: Double
    /// True when the deal is within `fairThreshold`.
    let isFair: Bool
    /// Winning roster id, or nil when the deal is fair.
    let winnerRosterId: Int?

    /// Deals within this share of the larger haul are graded as even.
    /// Mirrors `TradeEvaluation.fairThreshold`.
    static let fairThreshold: Double = 0.05

    func letter(for rosterId: Int) -> LetterGrade {
        lettersByRoster[rosterId] ?? .b
    }

    /// Grade a two-team trade from each side's acquired value.
    static func grade(
        sideA: (rosterId: Int, value: Int),
        sideB: (rosterId: Int, value: Int)
    ) -> TradeGrade {
        let total = sideA.value + sideB.value
        let diff = abs(sideA.value - sideB.value)
        let larger = max(sideA.value, sideB.value)
        let pct = larger > 0 ? Double(diff) / Double(larger) : 0
        let fair = pct <= fairThreshold

        let shareA = total > 0 ? Double(sideA.value) / Double(total) : 0.5
        let shareB = total > 0 ? Double(sideB.value) / Double(total) : 0.5

        let letters: [Int: LetterGrade] = [
            sideA.rosterId: LetterGrade(share: shareA),
            sideB.rosterId: LetterGrade(share: shareB),
        ]

        let winner: Int?
        if fair {
            winner = nil
        } else {
            winner = sideA.value >= sideB.value ? sideA.rosterId : sideB.rosterId
        }

        return TradeGrade(
            lettersByRoster: letters,
            differential: diff,
            percentGap: pct,
            isFair: fair,
            winnerRosterId: winner
        )
    }
}

// MARK: - LetterGrade

/// Letter grade for one side of a trade, derived from that side's share
/// of the total value exchanged. 50% ≈ B (fair); a lopsided winner
/// climbs toward A+, the loser slides toward F.
enum LetterGrade: String, Sendable, Hashable, CaseIterable {
    case aPlus  = "A+"
    case a      = "A"
    case aMinus = "A-"
    case bPlus  = "B+"
    case b      = "B"
    case bMinus = "B-"
    case cPlus  = "C+"
    case c      = "C"
    case d      = "D"
    case f      = "F"

    /// Map a 0...1 value share to a letter. Bands are symmetric around
    /// 0.50 so a fair trade grades both sides at B.
    init(share: Double) {
        switch share {
        case 0.620...:        self = .aPlus
        case 0.575..<0.620:   self = .a
        case 0.535..<0.575:   self = .aMinus
        case 0.515..<0.535:   self = .bPlus
        case 0.485..<0.515:   self = .b
        case 0.465..<0.485:   self = .bMinus
        case 0.425..<0.465:   self = .cPlus
        case 0.380..<0.425:   self = .c
        case 0.300..<0.380:   self = .d
        default:              self = .f
        }
    }

    /// Rough tier for tinting: win / fair / loss.
    var tier: Tier {
        switch self {
        case .aPlus, .a, .aMinus, .bPlus:   .win
        case .b:                            .fair
        case .bMinus, .cPlus, .c, .d, .f:   .loss
        }
    }

    enum Tier { case win, fair, loss }
}

// MARK: - Draft pick valuation

/// Pick-name helpers so historical trades value draft picks off the same
/// FantasyCalc catalog the trade analyzer uses. FantasyCalc pick names
/// are formatted as "{year} {round}" e.g. "2026 1st", "2027 2nd".
/// For current year, exact picks like "2026 Pick 1.03" are also available.
enum PickValuation {
    /// FantasyCalc catalog name for a season + round,
    /// e.g. `(2026, 1)` → "2026 1st".
    static func fantasyCalcName(season: String, round: Int) -> String {
        "\(season) \(ordinal(round))"
    }

    /// FantasyCalc catalog name for an exact pick slot,
    /// e.g. `(2026, 1, 3)` → "2026 Pick 1.03".
    static func exactPickName(season: String, round: Int, slot: Int) -> String {
        String(format: "%@ Pick %d.%02d", season, round, slot)
    }

    /// Human display name for a traded pick. If slot is known, shows exact
    /// position (e.g., "2026 1.03"), otherwise round only (e.g., "2026 1st").
    static func displayName(season: String, round: Int, slot: Int? = nil) -> String {
        if let slot {
            return String(format: "%@ %d.%02d", season, round, slot)
        }
        return "\(season) \(ordinal(round))"
    }

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1:  "1st"
        case 2:  "2nd"
        case 3:  "3rd"
        default: "\(n)th"
        }
    }
}
