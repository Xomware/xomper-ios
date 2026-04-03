import Foundation

// MARK: - Protocol

protocol XomperAPIClientProtocol: Sendable {
    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String]) async throws
    func sendRuleAcceptedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String]) async throws
    func sendRuleDeniedEmail(proposal: RuleProposalEmailPayload, approvedBy: [String], rejectedBy: [String], recipients: [String]) async throws
    func sendTaxiStealEmail(stealer: TaxiStealerPayload, player: TaxiPlayerPayload, owner: TaxiOwnerPayload, recipients: [String], leagueName: String) async throws
}

// MARK: - Request Payloads

struct RuleProposalEmailPayload: Encodable, Sendable {
    let title: String
    let description: String
    let proposedByUsername: String
    let leagueName: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case proposedByUsername = "proposed_by_username"
        case leagueName = "league_name"
    }
}

struct TaxiStealerPayload: Encodable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct TaxiPlayerPayload: Encodable, Sendable {
    let firstName: String
    let lastName: String
    let position: String
    let team: String
    let playerImageUrl: String
    let teamLogoUrl: String
    let pickCost: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case position
        case team
        case playerImageUrl = "player_image_url"
        case teamLogoUrl = "team_logo_url"
        case pickCost = "pick_cost"
    }
}

struct TaxiOwnerPayload: Encodable, Sendable {
    let displayName: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case email
    }
}

// MARK: - Response

struct XomperAPIResponse: Decodable, Sendable {
    let success: Bool
    let message: String

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case message = "Message"
    }
}

// MARK: - Errors

enum XomperAPIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case encodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid API URL"
        case .httpError(let code):
            "API returned status \(code)"
        case .encodingError(let error):
            "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Concrete Implementation

final class XomperAPIClient: XomperAPIClientProtocol {
    private let baseURL: String
    private let authToken: String
    private let session: URLSession
    private let encoder: JSONEncoder

    init(
        baseURL: String = Config.apiGatewayURL,
        authToken: String = "",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
        self.encoder = JSONEncoder()
    }

    // MARK: - Rule Emails

    func sendRuleProposalEmail(proposal: RuleProposalEmailPayload, recipients: [String]) async throws {
        let body: [String: Any] = [
            "proposal": [
                "title": proposal.title,
                "description": proposal.description,
                "proposed_by_username": proposal.proposedByUsername,
                "league_name": proposal.leagueName
            ],
            "recipients": recipients
        ]
        try await post("/email/rule-proposal", body: body)
    }

    func sendRuleAcceptedEmail(
        proposal: RuleProposalEmailPayload,
        approvedBy: [String],
        rejectedBy: [String],
        recipients: [String]
    ) async throws {
        let body: [String: Any] = [
            "proposal": [
                "title": proposal.title,
                "description": proposal.description,
                "proposed_by_username": proposal.proposedByUsername,
                "league_name": proposal.leagueName
            ],
            "approved_by": approvedBy,
            "rejected_by": rejectedBy,
            "recipients": recipients
        ]
        try await post("/email/rule-accept", body: body)
    }

    func sendRuleDeniedEmail(
        proposal: RuleProposalEmailPayload,
        approvedBy: [String],
        rejectedBy: [String],
        recipients: [String]
    ) async throws {
        let body: [String: Any] = [
            "proposal": [
                "title": proposal.title,
                "description": proposal.description,
                "proposed_by_username": proposal.proposedByUsername,
                "league_name": proposal.leagueName
            ],
            "approved_by": approvedBy,
            "rejected_by": rejectedBy,
            "recipients": recipients
        ]
        try await post("/email/rule-deny", body: body)
    }

    // MARK: - Taxi Steal Email

    func sendTaxiStealEmail(
        stealer: TaxiStealerPayload,
        player: TaxiPlayerPayload,
        owner: TaxiOwnerPayload,
        recipients: [String],
        leagueName: String
    ) async throws {
        let body: [String: Any] = [
            "stealer": ["display_name": stealer.displayName],
            "player": [
                "first_name": player.firstName,
                "last_name": player.lastName,
                "position": player.position,
                "team": player.team,
                "player_image_url": player.playerImageUrl,
                "team_logo_url": player.teamLogoUrl,
                "pick_cost": player.pickCost
            ],
            "owner": [
                "display_name": owner.displayName,
                "email": owner.email
            ],
            "recipients": recipients,
            "league_name": leagueName
        ]
        try await post("/email/taxi", body: body)
    }

    // MARK: - Private

    private func post(_ path: String, body: [String: Any]) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw XomperAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw XomperAPIError.encodingError(error)
        }

        let (_,  response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw XomperAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw XomperAPIError.httpError(statusCode: code)
        }
    }
}
