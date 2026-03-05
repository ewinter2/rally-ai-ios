import Foundation

enum SubstitutionError: Error, LocalizedError, Equatable {
    case setNotInitialized(setNumber: Int)
    case matchMismatch(expected: UUID, got: UUID)
    case invalidRotationIndex(Int)
    case playerOutNotInRotation(expectedPlayerID: UUID, actualPlayerID: UUID?)
    case playerOutNotOnCourt(playerID: UUID)
    case playerInAlreadyOnCourt(playerID: UUID)
    case playerInUnavailable(playerID: UUID)
    case playerLockedToDifferentRotation(playerID: UUID, requiredRotationIndex: Int)

    var errorDescription: String? {
        switch self {
        case .setNotInitialized(let setNumber):
            return "Set \(setNumber) is not initialized for substitutions."
        case .matchMismatch:
            return "Substitution does not match the active match."
        case .invalidRotationIndex(let index):
            return "Rotation index \(index) is invalid. Must be 1 through 6."
        case .playerOutNotInRotation:
            return "Player out does not match the player currently in that rotation slot."
        case .playerOutNotOnCourt:
            return "Player out is not currently on the court."
        case .playerInAlreadyOnCourt:
            return "Player in is already on the court."
        case .playerInUnavailable:
            return "Player in is not available for substitution."
        case .playerLockedToDifferentRotation:
            return "This player is already locked to a different rotation in this set."
        }
    }
}

struct SubstitutionLink: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let setNumber: Int
    let rotationIndex: Int
    let originalStarterPlayerID: UUID
    let pairedSubPlayerID: UUID
    let createdAt: Date
}

struct SubEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let setNumber: Int
    let rotationIndex: Int
    let playerOutID: UUID
    let playerInID: UUID
    let createdAt: Date
}

struct SetSubstitutionState: Codable, Equatable {
    let matchID: UUID
    let setNumber: Int
    var lineupByRotation: [Int: UUID] = [:]
    var substitutionLinks: [SubstitutionLink] = []
    // Per-set rotation lock: once a player appears in a rotation, they stay tied to it for that set.
    var playerRotationLocks: [UUID: Int] = [:]
    var substitutionHistory: [SubEvent] = []
    var playerStates: [UUID: PlayerMatchState] = [:]

    mutating func configureStartingLineup(_ lineup: [Int: UUID], timestamp: Date = Date()) throws {
        for rotationIndex in lineup.keys where !(1...6).contains(rotationIndex) {
            throw SubstitutionError.invalidRotationIndex(rotationIndex)
        }

        lineupByRotation = lineup

        for (rotationIndex, playerID) in lineup {
            var state = playerStates[playerID] ?? PlayerMatchState(
                id: UUID(),
                matchID: matchID,
                playerID: playerID,
                isOnCourt: false,
                isLibero: false,
                enteredAt: nil,
                exitedAt: nil,
                currentRotationIndex: nil,
                availableForSubstitution: true
            )

            state.isOnCourt = true
            state.currentRotationIndex = rotationIndex
            state.enteredAt = state.enteredAt ?? timestamp
            state.exitedAt = nil
            playerStates[playerID] = state
            playerRotationLocks[playerID] = rotationIndex
        }
    }

    mutating func applySubstitution(
        playerInID: UUID,
        playerOutID: UUID,
        rotationIndex: Int,
        allowOverride: Bool = false,
        timestamp: Date = Date()
    ) throws {
        guard (1...6).contains(rotationIndex) else {
            throw SubstitutionError.invalidRotationIndex(rotationIndex)
        }

        let currentInRotation = lineupByRotation[rotationIndex]
        guard currentInRotation == playerOutID else {
            throw SubstitutionError.playerOutNotInRotation(
                expectedPlayerID: playerOutID,
                actualPlayerID: currentInRotation
            )
        }

        var outgoing = playerStates[playerOutID] ?? PlayerMatchState(
            id: UUID(),
            matchID: matchID,
            playerID: playerOutID,
            isOnCourt: true,
            isLibero: false,
            enteredAt: nil,
            exitedAt: nil,
            currentRotationIndex: rotationIndex,
            availableForSubstitution: true
        )

        var incoming = playerStates[playerInID] ?? PlayerMatchState(
            id: UUID(),
            matchID: matchID,
            playerID: playerInID,
            isOnCourt: false,
            isLibero: false,
            enteredAt: nil,
            exitedAt: nil,
            currentRotationIndex: nil,
            availableForSubstitution: true
        )

        guard outgoing.isOnCourt else {
            throw SubstitutionError.playerOutNotOnCourt(playerID: playerOutID)
        }

        guard !incoming.isOnCourt else {
            throw SubstitutionError.playerInAlreadyOnCourt(playerID: playerInID)
        }

        guard incoming.availableForSubstitution else {
            throw SubstitutionError.playerInUnavailable(playerID: playerInID)
        }

        if !allowOverride,
           let lockedRotation = playerRotationLocks[playerInID],
           lockedRotation != rotationIndex {
            throw SubstitutionError.playerLockedToDifferentRotation(
                playerID: playerInID,
                requiredRotationIndex: lockedRotation
            )
        }

        if !allowOverride,
           let lockedRotation = playerRotationLocks[playerOutID],
           lockedRotation != rotationIndex {
            throw SubstitutionError.playerLockedToDifferentRotation(
                playerID: playerOutID,
                requiredRotationIndex: lockedRotation
            )
        }

        playerRotationLocks[playerInID] = rotationIndex
        playerRotationLocks[playerOutID] = rotationIndex
        substitutionLinks.append(
            SubstitutionLink(
                id: UUID(),
                matchID: matchID,
                setNumber: setNumber,
                rotationIndex: rotationIndex,
                originalStarterPlayerID: playerOutID,
                pairedSubPlayerID: playerInID,
                createdAt: timestamp
            )
        )

        lineupByRotation[rotationIndex] = playerInID

        outgoing.isOnCourt = false
        outgoing.currentRotationIndex = nil
        outgoing.exitedAt = timestamp

        incoming.isOnCourt = true
        incoming.currentRotationIndex = rotationIndex
        incoming.enteredAt = timestamp
        incoming.exitedAt = nil

        playerStates[playerOutID] = outgoing
        playerStates[playerInID] = incoming

        substitutionHistory.append(
            SubEvent(
                id: UUID(),
                matchID: matchID,
                setNumber: setNumber,
                rotationIndex: rotationIndex,
                playerOutID: playerOutID,
                playerInID: playerInID,
                createdAt: timestamp
            )
        )
    }

    func previousStarterForSub(playerID: UUID) -> UUID? {
        substitutionLinks
            .reversed()
            .first(where: { $0.pairedSubPlayerID == playerID })?
            .originalStarterPlayerID
    }
}

struct InGameState: Codable, Equatable {
    var sets: [Int: SetSubstitutionState] = [:]

    mutating func startSet(
        matchID: UUID,
        setNumber: Int,
        startingLineupByRotation: [Int: UUID] = [:],
        timestamp: Date = Date()
    ) throws {
        var setState = SetSubstitutionState(matchID: matchID, setNumber: setNumber)
        try setState.configureStartingLineup(startingLineupByRotation, timestamp: timestamp)
        sets[setNumber] = setState
    }

    mutating func ensureSet(
        matchID: UUID,
        setNumber: Int
    ) {
        if sets[setNumber] == nil {
            sets[setNumber] = SetSubstitutionState(matchID: matchID, setNumber: setNumber)
        }
    }

    mutating func configureStartingLineup(
        matchID: UUID,
        setNumber: Int,
        lineupByRotation: [Int: UUID],
        timestamp: Date = Date()
    ) throws {
        if sets[setNumber] == nil {
            sets[setNumber] = SetSubstitutionState(matchID: matchID, setNumber: setNumber)
        }

        guard var setState = sets[setNumber] else {
            throw SubstitutionError.setNotInitialized(setNumber: setNumber)
        }

        guard setState.matchID == matchID else {
            throw SubstitutionError.matchMismatch(expected: setState.matchID, got: matchID)
        }

        try setState.configureStartingLineup(lineupByRotation, timestamp: timestamp)
        sets[setNumber] = setState
    }

    mutating func applySubstitution(
        matchID: UUID,
        setNumber: Int,
        playerInID: UUID,
        playerOutID: UUID,
        rotationIndex: Int,
        allowOverride: Bool = false,
        timestamp: Date = Date()
    ) throws {
        guard var setState = sets[setNumber] else {
            throw SubstitutionError.setNotInitialized(setNumber: setNumber)
        }

        guard setState.matchID == matchID else {
            throw SubstitutionError.matchMismatch(expected: setState.matchID, got: matchID)
        }

        try setState.applySubstitution(
            playerInID: playerInID,
            playerOutID: playerOutID,
            rotationIndex: rotationIndex,
            allowOverride: allowOverride,
            timestamp: timestamp
        )

        sets[setNumber] = setState
    }

    func stateForSet(_ setNumber: Int) -> SetSubstitutionState? {
        sets[setNumber]
    }

    func previousStarterForSub(
        setNumber: Int,
        playerID: UUID
    ) -> UUID? {
        sets[setNumber]?.previousStarterForSub(playerID: playerID)
    }
}
