import Foundation

struct PlayoffBracketMatch: Codable, Identifiable, Sendable {
    let round: Int
    let matchId: Int
    let team1RosterId: Int?
    let team2RosterId: Int?
    let winnerRosterId: Int?
    let loserRosterId: Int?
    let team1From: BracketSource?
    let team2From: BracketSource?
    let placement: Int?

    var id: String { "r\(round)-m\(matchId)" }

    enum CodingKeys: String, CodingKey {
        case round = "r"
        case matchId = "m"
        case team1RosterId = "t1"
        case team2RosterId = "t2"
        case winnerRosterId = "w"
        case loserRosterId = "l"
        case team1From = "t1_from"
        case team2From = "t2_from"
        case placement = "p"
    }
}

struct BracketSource: Codable, Sendable {
    let winnerOfMatch: Int?
    let loserOfMatch: Int?

    enum CodingKeys: String, CodingKey {
        case winnerOfMatch = "w"
        case loserOfMatch = "l"
    }
}
