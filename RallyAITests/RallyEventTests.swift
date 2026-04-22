import XCTest
@testable import RallyTrack

// Tests for RallyEvent.fromBackend() — action parsing, pointAwardedTo mapping,
// ID resolution priority, and Codable round-trip.
@MainActor
final class RallyEventTests: XCTestCase {

    // MARK: - Shared fixtures

    private let teamID  = UUID()
    private let matchID = UUID()

    /// Convenience factory for a minimal BackendParsedEvent.
    private func backend(
        event: String,
        pointAwardedTo: String? = nil,
        playerNumber: Int? = nil,
        teamId: UUID? = nil,
        matchId: UUID? = nil,
        playerId: UUID? = nil,
        needsReview: Bool = false,
        rawText: String = ""
    ) -> BackendParsedEvent {
        BackendParsedEvent(
            playerNumber: playerNumber,
            event: event,
            pointAwardedTo: pointAwardedTo,
            needsReview: needsReview,
            rawText: rawText,
            playerId: playerId,
            teamId: teamId,
            matchId: matchId
        )
    }

    // MARK: - Action mapping

    func test_fromBackend_kill_mapsToKillAction() {
        let event = RallyEvent.fromBackend(backend(event: "KILL"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.action, .kill)
    }

    func test_fromBackend_ace_mapsToAceAction() {
        let event = RallyEvent.fromBackend(backend(event: "ACE"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.action, .ace)
    }

    func test_fromBackend_serve_mapsToServeAction() {
        let event = RallyEvent.fromBackend(backend(event: "SERVE"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.action, .serve)
    }

    func test_fromBackend_unknownString_mapsToUnknownAction() {
        let event = RallyEvent.fromBackend(backend(event: "NOT_A_REAL_EVENT"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.action, .unknown)
    }

    func test_fromBackend_lowercaseEvent_parsedCorrectly() {
        // Backend event strings are uppercased before matching
        let event = RallyEvent.fromBackend(backend(event: "kill"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.action, .kill)
    }

    func test_fromBackend_mixedCaseEvent_parsedCorrectly() {
        let event = RallyEvent.fromBackend(backend(event: "Ace"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.action, .ace)
    }

    // MARK: - pointAwardedTo mapping

    func test_fromBackend_pointAwardedTo_us() {
        let event = RallyEvent.fromBackend(backend(event: "ACE", pointAwardedTo: "us"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.pointAwardedTo, .us)
    }

    func test_fromBackend_pointAwardedTo_them() {
        let event = RallyEvent.fromBackend(backend(event: "SERVE_ERROR", pointAwardedTo: "them"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.pointAwardedTo, .them)
    }

    func test_fromBackend_pointAwardedTo_nil_isNil() {
        let event = RallyEvent.fromBackend(backend(event: "DIG", pointAwardedTo: nil), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertNil(event.pointAwardedTo)
    }

    func test_fromBackend_pointAwardedTo_uppercaseUs_parsedCorrectly() {
        // fromBackend lowercases the string before matching TeamSide
        let event = RallyEvent.fromBackend(backend(event: "ACE", pointAwardedTo: "US"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.pointAwardedTo, .us)
    }

    func test_fromBackend_pointAwardedTo_unknownString_isNil() {
        let event = RallyEvent.fromBackend(backend(event: "ACE", pointAwardedTo: "nobody"), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertNil(event.pointAwardedTo)
    }

    // MARK: - ID resolution

    func test_fromBackend_usesProvidedEventID() {
        let fixedID = UUID()
        let event = RallyEvent.fromBackend(backend(event: "UNKNOWN"), teamID: teamID, matchID: matchID, setNumber: 1, id: fixedID)
        XCTAssertEqual(event.id, fixedID)
    }

    func test_fromBackend_backendTeamID_overridesParamTeamID() {
        let backendTeamID = UUID()
        let event = RallyEvent.fromBackend(backend(event: "UNKNOWN", teamId: backendTeamID), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.teamID, backendTeamID)
    }

    func test_fromBackend_nilBackendTeamID_fallsBackToParam() {
        let event = RallyEvent.fromBackend(backend(event: "UNKNOWN", teamId: nil), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.teamID, teamID)
    }

    func test_fromBackend_backendMatchID_overridesParamMatchID() {
        let backendMatchID = UUID()
        let event = RallyEvent.fromBackend(backend(event: "UNKNOWN", matchId: backendMatchID), teamID: teamID, matchID: matchID, setNumber: 1)
        XCTAssertEqual(event.matchID, backendMatchID)
    }

    func test_fromBackend_backendPlayerID_overridesParamPlayerID() {
        let paramPlayerID   = UUID()
        let backendPlayerID = UUID()
        let event = RallyEvent.fromBackend(backend(event: "KILL", playerId: backendPlayerID), teamID: teamID, matchID: matchID, setNumber: 1, playerID: paramPlayerID)
        XCTAssertEqual(event.playerID, backendPlayerID)
    }

    func test_fromBackend_nilBackendPlayerID_fallsBackToParam() {
        let paramPlayerID = UUID()
        let event = RallyEvent.fromBackend(backend(event: "KILL", playerId: nil), teamID: teamID, matchID: matchID, setNumber: 1, playerID: paramPlayerID)
        XCTAssertEqual(event.playerID, paramPlayerID)
    }

    func test_fromBackend_setNumber_storedCorrectly() {
        let event = RallyEvent.fromBackend(backend(event: "ACE"), teamID: teamID, matchID: matchID, setNumber: 3)
        XCTAssertEqual(event.setNumber, 3)
    }

    // MARK: - Codable round-trip

    func test_rallyEvent_codableRoundTrip_preservesAllFields() throws {
        let original = RallyEvent(
            id: UUID(),
            createdAt: Date(),
            commandID: UUID(),
            teamID: teamID,
            matchID: matchID,
            setNumber: 2,
            playerID: UUID(),
            playerNumber: 7,
            action: .kill,
            backendEventRaw: "KILL",
            pointAwardedTo: .us,
            needsReview: false,
            rawText: "7 kill"
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RallyEvent.self, from: data)

        XCTAssertEqual(decoded.id,             original.id)
        XCTAssertEqual(decoded.action,         original.action)
        XCTAssertEqual(decoded.pointAwardedTo, original.pointAwardedTo)
        XCTAssertEqual(decoded.playerNumber,   original.playerNumber)
        XCTAssertEqual(decoded.setNumber,      original.setNumber)
        XCTAssertEqual(decoded.needsReview,    original.needsReview)
        XCTAssertEqual(decoded.rawText,        original.rawText)
    }
}
