import Foundation

/// Mirrors a row in the Supabase `whitelisted_leagues` table. The
/// `is_active=true` row is the league this build is configured for —
/// fetched at boot to avoid hardcoding a Sleeper league ID that drifts
/// every dynasty rollover.
struct WhitelistedLeague: Codable, Sendable, Identifiable {
    let id: String
    let leagueId: String
    let leagueName: String
    let season: String
    let isActive: Bool
    let isDynasty: Bool
    let hasTaxi: Bool
    let divisions: Int?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case leagueId = "league_id"
        case leagueName = "league_name"
        case season
        case isActive = "is_active"
        case isDynasty = "is_dynasty"
        case hasTaxi = "has_taxi"
        case divisions
        case size
    }
}
