import XCTest
@testable import RallyTrack

// Tests for GameState.apply() — the core scoring engine.
// Covers: addEvent, deleteEvent, replaceEvent, startNewSet, manualScore,
//         scoreForSet, and setsWonBeforeCurrentSet.
@MainActor
final class GameStateTests: XCTestCase {

    // MARK: - Shared fixtures

    private let matchID = UUID()
    private let teamID  = UUID()

    /// Convenience factory so individual tests stay readable.
    private func makeEvent(
        action: Action,
        pointAwardedTo: TeamSide? = nil,
        setNumber: Int = 1
    ) -> RallyEvent {
        RallyEvent(
            id: UUID(),
            createdAt: Date(),
            commandID: nil,
            teamID: teamID,
            matchID: matchID,
            setNumber: setNumber,
            playerID: nil,
            playerNumber: nil,
            action: action,
            backendEventRaw: action.rawValue,
            pointAwardedTo: pointAwardedTo,
            needsReview: false,
            rawText: ""
        )
    }

    // MARK: - addEvent

    func test_addEvent_usPoint_incrementsUsScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        XCTAssertEqual(state.score.us, 1)
        XCTAssertEqual(state.score.them, 0)
    }

    func test_addEvent_themPoint_incrementsThemScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .serveError, pointAwardedTo: .them)))
        XCTAssertEqual(state.score.us, 0)
        XCTAssertEqual(state.score.them, 1)
    }

    func test_addEvent_noPoint_doesNotChangeScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .dig, pointAwardedTo: nil)))
        XCTAssertEqual(state.score, Score(us: 0, them: 0))
    }

    func test_addMultipleEvents_accumulatesScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        for _ in 0..<3 { state.apply(.addEvent(makeEvent(action: .ace,  pointAwardedTo: .us)))   }
        for _ in 0..<2 { state.apply(.addEvent(makeEvent(action: .kill, pointAwardedTo: .them))) }
        XCTAssertEqual(state.score, Score(us: 3, them: 2))
    }

    func test_addEvent_onlyCountsCurrentSet() {
        var state = GameState(teamID: teamID, matchID: matchID)
        // An event tagged for set 2 should not affect the set-1 score
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us, setNumber: 2)))
        XCTAssertEqual(state.score, Score(us: 0, them: 0))
    }

    // MARK: - deleteEvent

    func test_deleteEvent_removesEventAndRecalculatesScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        let e1 = makeEvent(action: .ace, pointAwardedTo: .us)
        let e2 = makeEvent(action: .ace, pointAwardedTo: .us)
        state.apply(.addEvent(e1))
        state.apply(.addEvent(e2))
        state.apply(.deleteEvent(e1.id))
        XCTAssertEqual(state.score.us, 1)
        XCTAssertEqual(state.events.count, 1)
    }

    func test_deleteEvent_nonExistentID_isNoOp() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        state.apply(.deleteEvent(UUID()))
        XCTAssertEqual(state.score.us, 1) // score unchanged
        XCTAssertEqual(state.events.count, 1)
    }

    // MARK: - replaceEvent

    func test_replaceEvent_updatesActionAndScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        let original = makeEvent(action: .ace, pointAwardedTo: .us)
        state.apply(.addEvent(original))
        let replacement = makeEvent(action: .serveError, pointAwardedTo: .them)
        state.apply(.replaceEvent(original.id, with: replacement))
        XCTAssertEqual(state.score, Score(us: 0, them: 1))
    }

    func test_replaceEvent_preservesOriginalUUID() {
        var state = GameState(teamID: teamID, matchID: matchID)
        let original = makeEvent(action: .ace, pointAwardedTo: .us)
        state.apply(.addEvent(original))
        state.apply(.replaceEvent(original.id, with: makeEvent(action: .kill, pointAwardedTo: .us)))
        XCTAssertEqual(state.events.first?.id, original.id)
    }

    func test_replaceEvent_preservesCreatedAt() {
        var state = GameState(teamID: teamID, matchID: matchID)
        let original = makeEvent(action: .ace, pointAwardedTo: .us)
        state.apply(.addEvent(original))
        state.apply(.replaceEvent(original.id, with: makeEvent(action: .kill, pointAwardedTo: .us)))
        XCTAssertEqual(state.events.first?.createdAt, original.createdAt)
    }

    func test_replaceEvent_nonExistentID_isNoOp() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        let countBefore = state.events.count
        state.apply(.replaceEvent(UUID(), with: makeEvent(action: .kill, pointAwardedTo: .us)))
        XCTAssertEqual(state.events.count, countBefore)
    }

    // MARK: - startNewSet

    func test_startNewSet_snapshotsCurrentScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        state.apply(.addEvent(makeEvent(action: .kill, pointAwardedTo: .them)))
        state.apply(.startNewSet)
        XCTAssertEqual(state.completedSetScores[1], Score(us: 1, them: 1))
    }

    func test_startNewSet_incrementsSetNumber() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.startNewSet)
        XCTAssertEqual(state.currentSetNumber, 2)
    }

    func test_startNewSet_resetsScoreToZero() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        state.apply(.startNewSet)
        XCTAssertEqual(state.score, Score(us: 0, them: 0))
    }

    func test_startNewSet_clearsScoreAdjustment() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 5, them: 3))
        state.apply(.startNewSet)
        XCTAssertEqual(state.currentSetScoreAdjustment, ScoreAdjustment(us: 0, them: 0))
    }

    func test_startNewSet_snapshotIncludesManualAdjustment() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 25, them: 20))
        state.apply(.startNewSet)
        XCTAssertEqual(state.completedSetScores[1], Score(us: 25, them: 20))
    }

    // MARK: - manualScore

    func test_manualScore_setsScoreDirectly() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 10, them: 8))
        XCTAssertEqual(state.score, Score(us: 10, them: 8))
    }

    func test_manualScore_storesCorrectAdjustmentDelta() {
        var state = GameState(teamID: teamID, matchID: matchID)
        // 2 derived us points, 1 derived them point
        state.apply(.addEvent(makeEvent(action: .ace,  pointAwardedTo: .us)))
        state.apply(.addEvent(makeEvent(action: .ace,  pointAwardedTo: .us)))
        state.apply(.addEvent(makeEvent(action: .kill, pointAwardedTo: .them)))
        state.apply(.manualScore(us: 5, them: 4))
        XCTAssertEqual(state.score, Score(us: 5, them: 4))
        XCTAssertEqual(state.currentSetScoreAdjustment, ScoreAdjustment(us: 3, them: 3))
    }

    func test_manualScore_clampsNegativeInputToZero() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: -5, them: -3))
        XCTAssertEqual(state.score, Score(us: 0, them: 0))
    }

    func test_manualScore_subsequentEventsRespectAdjustment() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 3, them: 0)) // adjustment +3 us
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        XCTAssertEqual(state.score.us, 4) // 1 derived + 3 adjustment
    }

    // MARK: - scoreForSet

    func test_scoreForSet_currentSet_returnsLiveScore() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        XCTAssertEqual(state.scoreForSet(1), state.score)
    }

    func test_scoreForSet_completedSet_returnsSnapshot() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        state.apply(.startNewSet)
        // A set-2 event should not bleed into the set-1 snapshot
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .them, setNumber: 2)))
        XCTAssertEqual(state.scoreForSet(1), Score(us: 1, them: 0))
    }

    func test_scoreForSet_completedSet_snapshotOverridesDerivedScore() {
        // Manually adjusted score must persist in snapshot, not be re-derived
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.addEvent(makeEvent(action: .ace, pointAwardedTo: .us)))
        state.apply(.manualScore(us: 25, them: 20)) // adjustment applied
        state.apply(.startNewSet)
        XCTAssertEqual(state.scoreForSet(1), Score(us: 25, them: 20))
    }

    // MARK: - setsWonBeforeCurrentSet

    func test_setsWon_inSet1_returnsZeroZero() {
        let state = GameState(teamID: teamID, matchID: matchID)
        XCTAssertEqual(state.setsWonBeforeCurrentSet(), Score(us: 0, them: 0))
    }

    func test_setsWon_afterWinningSet1() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 25, them: 20))
        state.apply(.startNewSet)
        XCTAssertEqual(state.setsWonBeforeCurrentSet(), Score(us: 1, them: 0))
    }

    func test_setsWon_afterLosingSet1() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 20, them: 25))
        state.apply(.startNewSet)
        XCTAssertEqual(state.setsWonBeforeCurrentSet(), Score(us: 0, them: 1))
    }

    func test_setsWon_tiedSet_notCounted() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 25, them: 25))
        state.apply(.startNewSet)
        XCTAssertEqual(state.setsWonBeforeCurrentSet(), Score(us: 0, them: 0))
    }

    func test_setsWon_multipleSetsTalliedCorrectly() {
        var state = GameState(teamID: teamID, matchID: matchID)
        state.apply(.manualScore(us: 25, them: 20)); state.apply(.startNewSet) // us
        state.apply(.manualScore(us: 18, them: 25)); state.apply(.startNewSet) // them
        state.apply(.manualScore(us: 25, them: 22)); state.apply(.startNewSet) // us
        XCTAssertEqual(state.setsWonBeforeCurrentSet(), Score(us: 2, them: 1))
    }
}
