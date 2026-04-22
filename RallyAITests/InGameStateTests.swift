import XCTest
@testable import RallyTrack

// Tests for SetSubstitutionState — rotation math, lineup configuration,
// substitution validation, and the libero overlay system.
@MainActor
final class InGameStateTests: XCTestCase {

    // MARK: - Shared fixtures

    private var matchID   = UUID()
    private var playerIDs = [UUID]()

    override func setUp() {
        super.setUp()
        matchID   = UUID()
        // 6 starters (indices 0-5) + 2 bench players (indices 6-7)
        playerIDs = (0..<8).map { _ in UUID() }
    }

    /// Returns a SetSubstitutionState with players 0-5 assigned to slots 1-6.
    private func stateWithFullLineup(rotationNumber: Int = 1) throws -> SetSubstitutionState {
        var state = SetSubstitutionState(matchID: matchID, setNumber: 1)
        let lineup = Dictionary(uniqueKeysWithValues: (1...6).map { ($0, playerIDs[$0 - 1]) })
        try state.configureStartingLineup(lineup, currentRotationNumber: rotationNumber)
        return state
    }

    /// Adds a bench player to the state's playerStates so substitution checks pass.
    private func addBenchPlayer(_ state: inout SetSubstitutionState, index: Int) {
        let id = playerIDs[index]
        state.playerStates[id] = PlayerMatchState(
            id: UUID(), matchID: matchID, playerID: id,
            isOnCourt: false, isLibero: false,
            enteredAt: nil, exitedAt: nil,
            currentRotationIndex: nil, availableForSubstitution: true
        )
    }

    // MARK: - CourtPosition.isBackRow

    func test_isBackRow_positionsOneAndFiveAndSix() {
        XCTAssertTrue(CourtPosition.one.isBackRow)
        XCTAssertTrue(CourtPosition.five.isBackRow)
        XCTAssertTrue(CourtPosition.six.isBackRow)
    }

    func test_isBackRow_frontRowPositions() {
        XCTAssertFalse(CourtPosition.two.isBackRow)
        XCTAssertFalse(CourtPosition.three.isBackRow)
        XCTAssertFalse(CourtPosition.four.isBackRow)
    }

    // MARK: - configureStartingLineup

    func test_configureLineup_valid_assignsAllSixSlots() throws {
        let state = try stateWithFullLineup()
        XCTAssertEqual(state.rotationSlotAssignments.count, 6)
    }

    func test_configureLineup_valid_locksEachPlayerToTheirSlot() throws {
        let state = try stateWithFullLineup()
        for slot in 1...6 {
            XCTAssertEqual(state.playerRotationLocks[playerIDs[slot - 1]], slot)
        }
    }

    func test_configureLineup_valid_allPlayersMarkedOnCourt() throws {
        let state = try stateWithFullLineup()
        for slot in 1...6 {
            XCTAssertEqual(state.playerStates[playerIDs[slot - 1]]?.isOnCourt, true,
                           "Player in slot \(slot) should be on court")
        }
    }

    func test_configureLineup_duplicatePlayer_throwsDuplicateAssignment() {
        var state = SetSubstitutionState(matchID: matchID, setNumber: 1)
        var lineup = Dictionary(uniqueKeysWithValues: (1...6).map { ($0, playerIDs[$0 - 1]) })
        lineup[2] = lineup[1] // same player in slots 1 and 2
        XCTAssertThrowsError(try state.configureStartingLineup(lineup)) { error in
            guard case SubstitutionError.duplicatePlayerAssignment = error else {
                return XCTFail("Expected duplicatePlayerAssignment, got \(error)")
            }
        }
    }

    func test_configureLineup_invalidRotationIndex_throwsInvalidIndex() {
        var state = SetSubstitutionState(matchID: matchID, setNumber: 1)
        // Slot 0 is out of range
        let lineup: [Int: UUID] = [0: UUID(), 2: UUID(), 3: UUID(), 4: UUID(), 5: UUID(), 6: UUID()]
        XCTAssertThrowsError(try state.configureStartingLineup(lineup)) { error in
            guard case SubstitutionError.invalidRotationIndex = error else {
                return XCTFail("Expected invalidRotationIndex, got \(error)")
            }
        }
    }

    // MARK: - rotationSlot(forCourtPosition:)

    func test_rotationSlot_rotation1_identityMapping() throws {
        let state = try stateWithFullLineup(rotationNumber: 1)
        for pos in 1...6 {
            XCTAssertEqual(state.rotationSlot(forCourtPosition: pos), pos,
                           "At rotation 1, position \(pos) should map to slot \(pos)")
        }
    }

    func test_rotationSlot_rotation2_shiftsUp() throws {
        let state = try stateWithFullLineup(rotationNumber: 2)
        // pos 1 → slot 2, pos 6 → slot 1
        XCTAssertEqual(state.rotationSlot(forCourtPosition: 1), 2)
        XCTAssertEqual(state.rotationSlot(forCourtPosition: 6), 1)
    }

    func test_rotationSlot_rotation6_wrapsAround() throws {
        let state = try stateWithFullLineup(rotationNumber: 6)
        // pos 1 → slot 6, pos 2 → slot 1
        XCTAssertEqual(state.rotationSlot(forCourtPosition: 1), 6)
        XCTAssertEqual(state.rotationSlot(forCourtPosition: 2), 1)
    }

    // MARK: - courtPosition(forRotationSlot:) round-trip

    func test_rotationRoundTrip_positionToSlotAndBack() throws {
        for rotation in 1...6 {
            let state = try stateWithFullLineup(rotationNumber: rotation)
            for pos in 1...6 {
                let slot        = state.rotationSlot(forCourtPosition: pos)
                let backToPos   = state.courtPosition(forRotationSlot: slot)
                XCTAssertEqual(backToPos, pos,
                               "Round-trip failed at rotation \(rotation), position \(pos)")
            }
        }
    }

    // MARK: - applySubstitution — success

    func test_applySubstitution_valid_updatesRotationSlot() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[0], rotationIndex: 1)
        XCTAssertEqual(state.rotationSlotAssignments[1], playerIDs[6])
    }

    func test_applySubstitution_valid_inPlayerMarkedOnCourt() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[0], rotationIndex: 1)
        XCTAssertEqual(state.playerStates[playerIDs[6]]?.isOnCourt, true)
    }

    func test_applySubstitution_valid_outPlayerMarkedOffCourt() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[0], rotationIndex: 1)
        XCTAssertEqual(state.playerStates[playerIDs[0]]?.isOnCourt, false)
    }

    func test_applySubstitution_valid_recordsSubEvent() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[0], rotationIndex: 1)
        XCTAssertEqual(state.substitutionHistory.count, 1)
        XCTAssertEqual(state.substitutionHistory.first?.playerInID,  playerIDs[6])
        XCTAssertEqual(state.substitutionHistory.first?.playerOutID, playerIDs[0])
    }

    func test_applySubstitution_valid_locksBothPlayersToRotation() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[0], rotationIndex: 1)
        XCTAssertEqual(state.playerRotationLocks[playerIDs[6]], 1)
        XCTAssertEqual(state.playerRotationLocks[playerIDs[0]], 1)
    }

    // MARK: - applySubstitution — validation errors

    func test_applySubstitution_wrongPlayerOutForSlot_throws() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        // playerIDs[1] is in slot 2, not slot 1
        XCTAssertThrowsError(
            try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[1], rotationIndex: 1)
        ) { error in
            guard case SubstitutionError.playerOutNotInRotation = error else {
                return XCTFail("Expected playerOutNotInRotation, got \(error)")
            }
        }
    }

    func test_applySubstitution_playerInAlreadyOnCourt_throws() throws {
        var state = try stateWithFullLineup()
        // playerIDs[1] is already on court in slot 2
        XCTAssertThrowsError(
            try state.applySubstitution(playerInID: playerIDs[1], playerOutID: playerIDs[0], rotationIndex: 1)
        ) { error in
            guard case SubstitutionError.playerInAlreadyOnCourt = error else {
                return XCTFail("Expected playerInAlreadyOnCourt, got \(error)")
            }
        }
    }

    func test_applySubstitution_invalidRotationIndex_throws() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        XCTAssertThrowsError(
            try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[0], rotationIndex: 0)
        ) { error in
            guard case SubstitutionError.invalidRotationIndex = error else {
                return XCTFail("Expected invalidRotationIndex, got \(error)")
            }
        }
    }

    func test_applySubstitution_playerLockedToDifferentSlot_throws() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        state.playerRotationLocks[playerIDs[6]] = 3 // locked to slot 3, trying to enter slot 1
        XCTAssertThrowsError(
            try state.applySubstitution(playerInID: playerIDs[6], playerOutID: playerIDs[0], rotationIndex: 1)
        ) { error in
            guard case SubstitutionError.playerLockedToDifferentRotation = error else {
                return XCTFail("Expected playerLockedToDifferentRotation, got \(error)")
            }
        }
    }

    func test_applySubstitution_allowOverride_bypassesRotationLock() throws {
        var state = try stateWithFullLineup()
        addBenchPlayer(&state, index: 6)
        state.playerRotationLocks[playerIDs[6]] = 3 // locked to slot 3
        // allowOverride should bypass the lock check
        XCTAssertNoThrow(
            try state.applySubstitution(
                playerInID: playerIDs[6],
                playerOutID: playerIDs[0],
                rotationIndex: 1,
                allowOverride: true
            )
        )
        XCTAssertEqual(state.rotationSlotAssignments[1], playerIDs[6])
    }

    // MARK: - rotateClockwise

    func test_rotateClockwise_incrementsRotationNumber() throws {
        var state = try stateWithFullLineup(rotationNumber: 1)
        state.rotateClockwise()
        XCTAssertEqual(state.currentRotationNumber, 2)
    }

    func test_rotateClockwise_wrapsFrom6To1() throws {
        var state = try stateWithFullLineup(rotationNumber: 6)
        state.rotateClockwise()
        XCTAssertEqual(state.currentRotationNumber, 1)
    }
}
