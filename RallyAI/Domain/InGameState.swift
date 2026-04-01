import Foundation

enum SubstitutionError: Error, LocalizedError, Equatable {
    case setNotInitialized(setNumber: Int)
    case matchMismatch(expected: UUID, got: UUID)
    case invalidRotationIndex(Int)
    case duplicatePlayerAssignment(playerID: UUID)
    case liberoAlreadyActive(playerID: UUID)
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
        case .duplicatePlayerAssignment:
            return "That player is already assigned to a different rotation slot."
        case .liberoAlreadyActive:
            return "Only one libero can be active on the court at one time."
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

struct SubEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let setNumber: Int
    let rotationIndex: Int
    let playerOutID: UUID
    let playerInID: UUID
    let createdAt: Date
}

enum CourtPosition: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6

    var id: Int { rawValue }

    var isBackRow: Bool {
        rawValue == 1 || rawValue == 5 || rawValue == 6
    }
}

struct SetSubstitutionState: Codable, Equatable {
    let matchID: UUID
    let setNumber: Int
    // Persistent six-slot rotation containers. Players stay tied to their slot as the team rotates.
    var rotationSlotAssignments: [Int: UUID] = [:]
    var currentRotationNumber: Int = 1
    // Active libero overlays keyed by rotation slot.
    var activeLiberoAssignments: [Int: UUID] = [:]
    var liberoServingRotationSlot: Int?
    // Per-set rotation lock: once a player appears in a rotation, they stay tied to it for that set.
    var playerRotationLocks: [UUID: Int] = [:]
    var substitutionHistory: [SubEvent] = []
    var playerStates: [UUID: PlayerMatchState] = [:]

    private enum CodingKeys: String, CodingKey {
        case matchID
        case setNumber
        case rotationSlotAssignments
        case lineupByRotation
        case currentRotationNumber
        case activeLiberoAssignments
        case liberoServingRotationSlot
        case playerRotationLocks
        case substitutionHistory
        case playerStates
    }

    init(
        matchID: UUID,
        setNumber: Int,
        rotationSlotAssignments: [Int: UUID] = [:],
        currentRotationNumber: Int = 1,
        activeLiberoAssignments: [Int: UUID] = [:],
        liberoServingRotationSlot: Int? = nil,
        playerRotationLocks: [UUID: Int] = [:],
        substitutionHistory: [SubEvent] = [],
        playerStates: [UUID: PlayerMatchState] = [:]
    ) {
        self.matchID = matchID
        self.setNumber = setNumber
        self.rotationSlotAssignments = rotationSlotAssignments
        self.currentRotationNumber = min(max(currentRotationNumber, 1), 6)
        self.activeLiberoAssignments = activeLiberoAssignments
        self.liberoServingRotationSlot = liberoServingRotationSlot
        self.playerRotationLocks = playerRotationLocks
        self.substitutionHistory = substitutionHistory
        self.playerStates = playerStates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchID = try container.decode(UUID.self, forKey: .matchID)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        rotationSlotAssignments = try container.decodeIfPresent([Int: UUID].self, forKey: .rotationSlotAssignments)
            ?? container.decodeIfPresent([Int: UUID].self, forKey: .lineupByRotation)
            ?? [:]
        currentRotationNumber = min(max(try container.decodeIfPresent(Int.self, forKey: .currentRotationNumber) ?? 1, 1), 6)
        activeLiberoAssignments = try container.decodeIfPresent([Int: UUID].self, forKey: .activeLiberoAssignments) ?? [:]
        liberoServingRotationSlot = try container.decodeIfPresent(Int.self, forKey: .liberoServingRotationSlot)
        playerRotationLocks = try container.decodeIfPresent([UUID: Int].self, forKey: .playerRotationLocks) ?? [:]
        substitutionHistory = try container.decodeIfPresent([SubEvent].self, forKey: .substitutionHistory) ?? []
        playerStates = try container.decodeIfPresent([UUID: PlayerMatchState].self, forKey: .playerStates) ?? [:]
        rebuildPlayerStates()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matchID, forKey: .matchID)
        try container.encode(setNumber, forKey: .setNumber)
        try container.encode(rotationSlotAssignments, forKey: .rotationSlotAssignments)
        try container.encode(currentRotationNumber, forKey: .currentRotationNumber)
        try container.encode(activeLiberoAssignments, forKey: .activeLiberoAssignments)
        try container.encodeIfPresent(liberoServingRotationSlot, forKey: .liberoServingRotationSlot)
        try container.encode(playerRotationLocks, forKey: .playerRotationLocks)
        try container.encode(substitutionHistory, forKey: .substitutionHistory)
        try container.encode(playerStates, forKey: .playerStates)
    }

    mutating func configureStartingLineup(
        _ lineup: [Int: UUID],
        currentRotationNumber: Int = 1,
        timestamp: Date = Date()
    ) throws {
        for rotationIndex in lineup.keys where !(1...6).contains(rotationIndex) {
            throw SubstitutionError.invalidRotationIndex(rotationIndex)
        }

        if Set(lineup.values).count != lineup.values.count {
            guard let duplicateID = Dictionary(grouping: lineup.values, by: { $0 })
                .first(where: { $0.value.count > 1 })?.key else {
                throw SubstitutionError.duplicatePlayerAssignment(playerID: UUID())
            }
            throw SubstitutionError.duplicatePlayerAssignment(playerID: duplicateID)
        }

        self.currentRotationNumber = min(max(currentRotationNumber, 1), 6)
        rotationSlotAssignments = lineup
        activeLiberoAssignments = activeLiberoAssignments.filter { lineup[$0.key] != nil }

        for (rotationIndex, playerID) in lineup {
            playerRotationLocks[playerID] = rotationIndex
        }

        removeInvalidLiberoAssignments()
        rebuildPlayerStates(timestamp: timestamp)
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

        let currentInRotation = rotationSlotAssignments[rotationIndex]
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
        rotationSlotAssignments[rotationIndex] = playerInID
        activeLiberoAssignments.removeValue(forKey: rotationIndex)

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

        rebuildPlayerStates(timestamp: timestamp)
    }

    func previousStarterForSub(playerID: UUID) -> UUID? {
        substitutionHistory
            .reversed()
            .first(where: { $0.playerInID == playerID })?
            .playerOutID
    }

    mutating func setCurrentRotationNumber(_ rotationNumber: Int, timestamp: Date = Date()) {
        currentRotationNumber = min(max(rotationNumber, 1), 6)
        removeInvalidLiberoAssignments()
        rebuildPlayerStates(timestamp: timestamp)
    }

    mutating func rotateClockwise(timestamp: Date = Date()) {
        currentRotationNumber = currentRotationNumber == 6 ? 1 : currentRotationNumber + 1
        removeInvalidLiberoAssignments()
        rebuildPlayerStates(timestamp: timestamp)
    }

    mutating func setPlayer(
        _ playerID: UUID?,
        forCourtPosition courtPosition: Int,
        timestamp: Date = Date()
    ) throws {
        guard (1...6).contains(courtPosition) else {
            throw SubstitutionError.invalidRotationIndex(courtPosition)
        }

        let rotationSlot = rotationSlot(forCourtPosition: courtPosition)

        if let playerID {
            if let existingSlot = rotationSlotAssignments.first(where: { $0.value == playerID })?.key,
               existingSlot != rotationSlot {
                throw SubstitutionError.duplicatePlayerAssignment(playerID: playerID)
            }
            rotationSlotAssignments[rotationSlot] = playerID
            playerRotationLocks[playerID] = rotationSlot
        } else {
            if let removedPlayerID = rotationSlotAssignments.removeValue(forKey: rotationSlot) {
                playerRotationLocks.removeValue(forKey: removedPlayerID)
            }
            activeLiberoAssignments.removeValue(forKey: rotationSlot)
        }

        rebuildPlayerStates(timestamp: timestamp)
    }

    mutating func setLibero(
        _ liberoPlayerID: UUID?,
        forCourtPosition courtPosition: Int,
        timestamp: Date = Date()
    ) throws {
        guard let courtPosition = CourtPosition(rawValue: courtPosition) else {
            throw SubstitutionError.invalidRotationIndex(courtPosition)
        }

        guard courtPosition.isBackRow else {
            return
        }

        let rotationSlot = rotationSlot(forCourtPosition: courtPosition.rawValue)
        guard rotationSlotAssignments[rotationSlot] != nil else {
            activeLiberoAssignments.removeValue(forKey: rotationSlot)
            rebuildPlayerStates(timestamp: timestamp)
            return
        }

        if let liberoPlayerID {
            if let existingActiveLibero = activeLiberoAssignments.first(where: { $0.key != rotationSlot })?.value,
               existingActiveLibero != liberoPlayerID {
                throw SubstitutionError.liberoAlreadyActive(playerID: existingActiveLibero)
            }
            if rotationSlotAssignments.values.contains(liberoPlayerID) {
                throw SubstitutionError.playerInAlreadyOnCourt(playerID: liberoPlayerID)
            }
            if let existingRotationSlot = activeLiberoAssignments.first(where: { $0.value == liberoPlayerID })?.key,
               existingRotationSlot != rotationSlot {
                throw SubstitutionError.playerLockedToDifferentRotation(
                    playerID: liberoPlayerID,
                    requiredRotationIndex: existingRotationSlot
                )
            }
            activeLiberoAssignments[rotationSlot] = liberoPlayerID
            playerRotationLocks[liberoPlayerID] = rotationSlot
        } else {
            activeLiberoAssignments.removeValue(forKey: rotationSlot)
        }

        removeInvalidLiberoAssignments()
        rebuildPlayerStates(timestamp: timestamp)
    }

    func rotationSlot(forCourtPosition courtPosition: Int) -> Int {
        ((currentRotationNumber + courtPosition - 2) % 6) + 1
    }

    func courtPosition(forRotationSlot rotationSlot: Int) -> Int {
        ((rotationSlot - currentRotationNumber + 6) % 6) + 1
    }

    func truePlayerID(atCourtPosition courtPosition: Int) -> UUID? {
        rotationSlotAssignments[rotationSlot(forCourtPosition: courtPosition)]
    }

    func effectivePlayerID(atCourtPosition courtPosition: Int) -> UUID? {
        let rotationSlot = rotationSlot(forCourtPosition: courtPosition)
        return activeLiberoAssignments[rotationSlot] ?? rotationSlotAssignments[rotationSlot]
    }

    func activeLiberoPlayerID(atCourtPosition courtPosition: Int) -> UUID? {
        activeLiberoAssignments[rotationSlot(forCourtPosition: courtPosition)]
    }

    func currentServerPlayerID() -> UUID? {
        effectivePlayerID(atCourtPosition: 1)
    }

    private mutating func removeInvalidLiberoAssignments() {
        activeLiberoAssignments = activeLiberoAssignments.filter { rotationSlot, liberoID in
            rotationSlotAssignments[rotationSlot] != nil
                && CourtPosition(rawValue: courtPosition(forRotationSlot: rotationSlot))?.isBackRow == true
                && liberoID != rotationSlotAssignments[rotationSlot]
        }
    }

    private mutating func rebuildPlayerStates(timestamp: Date = Date()) {
        let knownPlayerIDs = Set(playerStates.keys)
            .union(rotationSlotAssignments.values)
            .union(activeLiberoAssignments.values)

        var rebuiltStates: [UUID: PlayerMatchState] = [:]

        for playerID in knownPlayerIDs {
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

            state.isOnCourt = false
            state.isLibero = false
            state.currentRotationIndex = nil
            state.exitedAt = timestamp
            rebuiltStates[playerID] = state
        }

        for (rotationSlot, playerID) in rotationSlotAssignments {
            guard activeLiberoAssignments[rotationSlot] == nil else { continue }
            var state = rebuiltStates[playerID] ?? PlayerMatchState(
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
            state.isLibero = false
            state.currentRotationIndex = rotationSlot
            state.enteredAt = state.enteredAt ?? timestamp
            state.exitedAt = nil
            rebuiltStates[playerID] = state
        }

        for (rotationSlot, liberoPlayerID) in activeLiberoAssignments {
            var liberoState = rebuiltStates[liberoPlayerID] ?? PlayerMatchState(
                id: UUID(),
                matchID: matchID,
                playerID: liberoPlayerID,
                isOnCourt: false,
                isLibero: true,
                enteredAt: nil,
                exitedAt: nil,
                currentRotationIndex: nil,
                availableForSubstitution: true
            )
            liberoState.isOnCourt = true
            liberoState.isLibero = true
            liberoState.currentRotationIndex = rotationSlot
            liberoState.enteredAt = liberoState.enteredAt ?? timestamp
            liberoState.exitedAt = nil
            rebuiltStates[liberoPlayerID] = liberoState
        }

        playerStates = rebuiltStates
    }
}

struct InGameState: Codable, Equatable {
    var sets: [Int: SetSubstitutionState] = [:]

    mutating func startSet(
        matchID: UUID,
        setNumber: Int,
        startingLineupByRotation: [Int: UUID] = [:],
        currentRotationNumber: Int = 1,
        timestamp: Date = Date()
    ) throws {
        var setState = SetSubstitutionState(matchID: matchID, setNumber: setNumber)
        try setState.configureStartingLineup(
            startingLineupByRotation,
            currentRotationNumber: currentRotationNumber,
            timestamp: timestamp
        )
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
        currentRotationNumber: Int = 1,
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

        try setState.configureStartingLineup(
            lineupByRotation,
            currentRotationNumber: currentRotationNumber,
            timestamp: timestamp
        )
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

    mutating func setCurrentRotationNumber(
        matchID: UUID,
        setNumber: Int,
        rotationNumber: Int,
        timestamp: Date = Date()
    ) throws {
        guard var setState = sets[setNumber] else {
            throw SubstitutionError.setNotInitialized(setNumber: setNumber)
        }

        guard setState.matchID == matchID else {
            throw SubstitutionError.matchMismatch(expected: setState.matchID, got: matchID)
        }

        setState.setCurrentRotationNumber(rotationNumber, timestamp: timestamp)
        sets[setNumber] = setState
    }

    mutating func rotateClockwise(
        matchID: UUID,
        setNumber: Int,
        timestamp: Date = Date()
    ) throws {
        guard var setState = sets[setNumber] else {
            throw SubstitutionError.setNotInitialized(setNumber: setNumber)
        }

        guard setState.matchID == matchID else {
            throw SubstitutionError.matchMismatch(expected: setState.matchID, got: matchID)
        }

        setState.rotateClockwise(timestamp: timestamp)
        sets[setNumber] = setState
    }

    mutating func setPlayer(
        matchID: UUID,
        setNumber: Int,
        playerID: UUID?,
        forCourtPosition courtPosition: Int,
        timestamp: Date = Date()
    ) throws {
        guard var setState = sets[setNumber] else {
            throw SubstitutionError.setNotInitialized(setNumber: setNumber)
        }

        guard setState.matchID == matchID else {
            throw SubstitutionError.matchMismatch(expected: setState.matchID, got: matchID)
        }

        try setState.setPlayer(playerID, forCourtPosition: courtPosition, timestamp: timestamp)
        sets[setNumber] = setState
    }

    mutating func setLibero(
        matchID: UUID,
        setNumber: Int,
        liberoPlayerID: UUID?,
        forCourtPosition courtPosition: Int,
        timestamp: Date = Date()
    ) throws {
        guard var setState = sets[setNumber] else {
            throw SubstitutionError.setNotInitialized(setNumber: setNumber)
        }

        guard setState.matchID == matchID else {
            throw SubstitutionError.matchMismatch(expected: setState.matchID, got: matchID)
        }

        try setState.setLibero(liberoPlayerID, forCourtPosition: courtPosition, timestamp: timestamp)
        sets[setNumber] = setState
    }

    mutating func removePlayer(
        matchID: UUID,
        playerID: UUID
    ) {
        for setNumber in sets.keys {
            guard var setState = sets[setNumber], setState.matchID == matchID else { continue }

            setState.rotationSlotAssignments = setState.rotationSlotAssignments.filter { $0.value != playerID }
            setState.activeLiberoAssignments = setState.activeLiberoAssignments.filter { $0.value != playerID }
            setState.playerRotationLocks.removeValue(forKey: playerID)
            setState.playerStates.removeValue(forKey: playerID)
            setState.substitutionHistory.removeAll {
                $0.playerInID == playerID || $0.playerOutID == playerID
            }
            setState.setCurrentRotationNumber(setState.currentRotationNumber)

            sets[setNumber] = setState
        }
    }

    mutating func removeLiberoPlayer(
        matchID: UUID,
        playerID: UUID
    ) {
        for setNumber in sets.keys {
            guard var setState = sets[setNumber], setState.matchID == matchID else { continue }

            setState.activeLiberoAssignments = setState.activeLiberoAssignments.filter { $0.value != playerID }
            setState.playerStates.removeValue(forKey: playerID)
            setState.setCurrentRotationNumber(setState.currentRotationNumber)

            sets[setNumber] = setState
        }
    }
}
