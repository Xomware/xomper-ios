import XCTest
@testable import Xomper

/// Tests for `MockDraftStore.proxySlotOrder(rosters:users:)` — the
/// prior-season-standings fallback used when Sleeper has no upcoming
/// draft (most of the off-season).
///
/// The static helper is pure (no store, no dependency graph), so these
/// tests stay fast and focused.
@MainActor
final class MockDraftStoreFallbackTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a `Roster` with the supplied wins / fpts. Other settings
    /// fields are zeroed since the proxy only reads `wins` and the
    /// roster's `pointsFor` computed property.
    private func makeRoster(
        rosterId: Int,
        ownerId: String,
        wins: Int,
        fpts: Int
    ) -> Roster {
        // `RosterSettings` only has `init(from decoder:)`; build the
        // raw JSON and decode so the fixture stays valid as fields
        // shift over time.
        let json: [String: Any] = [
            "roster_id": rosterId,
            "owner_id": ownerId,
            "league_id": "L1",
            "settings": [
                "wins": wins,
                "losses": 0,
                "ties": 0,
                "division": 0,
                "fpts": fpts,
                "fpts_decimal": 0,
                "fpts_against": 0,
                "fpts_against_decimal": 0
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Roster.self, from: data)
    }

    private func makeUser(
        userId: String,
        displayName: String? = nil,
        teamName: String? = nil
    ) -> SleeperUser {
        var json: [String: Any] = [
            "user_id": userId,
            "username": userId
        ]
        if let displayName {
            json["display_name"] = displayName
        }
        if let teamName {
            json["metadata"] = ["team_name": teamName]
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(SleeperUser.self, from: data)
    }

    // MARK: - Test 1: empty rosters returns empty dict

    func testProxySlotOrder_emptyRosters_returnsEmpty() {
        let slots = MockDraftStore.proxySlotOrder(rosters: [], users: [])
        XCTAssertTrue(slots.isEmpty)
    }

    // MARK: - Test 2: worst record gets slot 1, best gets slot N

    func testProxySlotOrder_sortsWorstFirst() {
        let rosters = [
            makeRoster(rosterId: 1, ownerId: "u1", wins: 10, fpts: 1500),
            makeRoster(rosterId: 2, ownerId: "u2", wins: 2, fpts: 1100),
            makeRoster(rosterId: 3, ownerId: "u3", wins: 7, fpts: 1300),
            makeRoster(rosterId: 4, ownerId: "u4", wins: 5, fpts: 1200)
        ]
        let users = [
            makeUser(userId: "u1", teamName: "Champs"),
            makeUser(userId: "u2", teamName: "Cellar"),
            makeUser(userId: "u3", teamName: "Mid"),
            makeUser(userId: "u4", teamName: "Lower")
        ]

        let slots = MockDraftStore.proxySlotOrder(rosters: rosters, users: users)

        // Worst (2 wins) → slot 1
        XCTAssertEqual(slots[1]?.rosterId, 2)
        XCTAssertEqual(slots[1]?.teamName, "Cellar")
        // Next worst (5 wins) → slot 2
        XCTAssertEqual(slots[2]?.rosterId, 4)
        XCTAssertEqual(slots[2]?.teamName, "Lower")
        // 7 wins → slot 3
        XCTAssertEqual(slots[3]?.rosterId, 3)
        XCTAssertEqual(slots[3]?.teamName, "Mid")
        // Best (10 wins) → slot 4
        XCTAssertEqual(slots[4]?.rosterId, 1)
        XCTAssertEqual(slots[4]?.teamName, "Champs")
    }

    // MARK: - Test 3: tie on wins → pointsFor breaks the tie (lower first)

    func testProxySlotOrder_tieOnWins_pointsForBreaksTie() {
        let rosters = [
            makeRoster(rosterId: 10, ownerId: "u10", wins: 6, fpts: 1300),
            makeRoster(rosterId: 11, ownerId: "u11", wins: 6, fpts: 1100),
            makeRoster(rosterId: 12, ownerId: "u12", wins: 6, fpts: 1200)
        ]
        let users = [
            makeUser(userId: "u10"),
            makeUser(userId: "u11"),
            makeUser(userId: "u12")
        ]

        let slots = MockDraftStore.proxySlotOrder(rosters: rosters, users: users)

        XCTAssertEqual(slots[1]?.rosterId, 11, "Lowest fpts (1100) gets slot 1")
        XCTAssertEqual(slots[2]?.rosterId, 12, "Middle fpts (1200) gets slot 2")
        XCTAssertEqual(slots[3]?.rosterId, 10, "Highest fpts (1300) gets slot 3")
    }

    // MARK: - Test 4: team name preference (team_name > display_name > "Slot N")

    func testProxySlotOrder_teamNameFallsBackThroughChain() {
        let rosters = [
            makeRoster(rosterId: 1, ownerId: "u1", wins: 1, fpts: 0),
            makeRoster(rosterId: 2, ownerId: "u2", wins: 2, fpts: 0),
            makeRoster(rosterId: 3, ownerId: "u-missing", wins: 3, fpts: 0)
        ]
        let users = [
            makeUser(userId: "u1", teamName: "Tigers"),
            makeUser(userId: "u2", displayName: "DisplayName")
        ]

        let slots = MockDraftStore.proxySlotOrder(rosters: rosters, users: users)

        XCTAssertEqual(slots[1]?.teamName, "Tigers", "team_name preferred when present")
        XCTAssertEqual(slots[2]?.teamName, "DisplayName", "displayName when no team_name")
        // u-missing isn't in users — falls back to "Slot N" (slot 3).
        XCTAssertEqual(slots[3]?.teamName, "Slot 3")
    }

    // MARK: - Test 5: slot dict covers exactly N entries (one per roster)

    func testProxySlotOrder_coversEveryRoster() {
        let rosters = (1...12).map { id in
            makeRoster(rosterId: id, ownerId: "u\(id)", wins: id, fpts: id * 100)
        }
        let users = (1...12).map { makeUser(userId: "u\($0)") }

        let slots = MockDraftStore.proxySlotOrder(rosters: rosters, users: users)

        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(Set(slots.keys), Set(1...12))
        let coveredRosters = Set(slots.values.map(\.rosterId))
        XCTAssertEqual(coveredRosters, Set(1...12))
    }

    // MARK: - Test 6: missing owner_id → empty userId, falls back to "Slot N"

    func testProxySlotOrder_nilOwnerId_doesNotCrash() {
        // Manually craft a roster with no owner_id key.
        let json: [String: Any] = [
            "roster_id": 7,
            "league_id": "L1",
            "settings": [
                "wins": 0,
                "losses": 0,
                "ties": 0,
                "division": 0,
                "fpts": 0,
                "fpts_decimal": 0,
                "fpts_against": 0,
                "fpts_against_decimal": 0
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let roster = try! JSONDecoder().decode(Roster.self, from: data)

        let slots = MockDraftStore.proxySlotOrder(rosters: [roster], users: [])

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[1]?.rosterId, 7)
        XCTAssertEqual(slots[1]?.userId, "")
        XCTAssertEqual(slots[1]?.teamName, "Slot 1")
    }
}
