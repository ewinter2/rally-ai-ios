//
//  TrackingViewModel.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/12/26.
//
import Foundation
import Combine

struct CourtSlotDisplay: Identifiable, Equatable {
    let courtPosition: Int
    let truePlayer: Player?
    let effectivePlayer: Player?
    let liberoPlayer: Player?

    var id: Int { courtPosition }
    var isLiberoOverlayActive: Bool { liberoPlayer != nil }
}

struct DesignatedLiberoSlotDisplay: Identifiable, Equatable {
    let slotNumber: Int
    let player: Player?

    var id: Int { slotNumber }
    var label: String { "L\(slotNumber)" }
}

@MainActor
final class TrackingViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published private(set) var appState: AppState = AppState()
    @Published private(set) var gameState: GameState = GameState()
    @Published private(set) var commandQueue: [CommandInput] = []
    @Published private(set) var inGameState: InGameState = InGameState()
    @Published var rosterState: RosterState = RosterState()

    private let backend: BackendClientProtocol
    private let stateStore: LocalStateStoreProtocol

    init(
        backend: BackendClientProtocol? = nil,
        stateStore: LocalStateStoreProtocol? = nil,
        restoreOnInit: Bool = true
    ) {
        self.backend = backend ?? BackendClient()
        self.stateStore = stateStore ?? LocalStateStore()
        inGameState.ensureSet(matchID: gameState.matchID, setNumber: gameState.currentSetNumber)

        if restoreOnInit {
            Task { await restoreState() }
        }
    }

    var currentSetNumber: Int { gameState.currentSetNumber }
    var score: Score { gameState.score }
    var setsWon: Score { gameState.setsWonBeforeCurrentSet() }
    var activeMatchID: UUID? { appState.activeMatchID }
    var activeMatch: Match? {
        guard let session = activeSession else { return nil }
        return session.match
    }
    var isActiveMatchCompleted: Bool { activeMatch?.isCompleted ?? false }
    var savedMatches: [MatchSession] {
        appState.matches.sorted { $0.updatedAt > $1.updatedAt }
    }
    /// The team that has won the current set, or nil if the set is still in progress.
    /// Uses standard volleyball rules: first to 25 (15 in set 5), must lead by 2.
    var setWinningTeam: TeamSide? {
        let s = score
        let target = currentSetNumber == 5 ? 15 : 25
        if s.us >= target && s.us - s.them >= 2 { return .us }
        if s.them >= target && s.them - s.us >= 2 { return .them }
        return nil
    }

    var currentRotationNumber: Int {
        inGameState.stateForSet(gameState.currentSetNumber)?.currentRotationNumber ?? 1
    }

    var currentServer: Player? {
        guard
            let serverID = inGameState.stateForSet(gameState.currentSetNumber)?.currentServerPlayerID()
        else {
            return nil
        }

        return rosterState.playerByID(serverID)
    }

    var activeLiberoPlayers: [Player] {
        guard let setState = inGameState.stateForSet(gameState.currentSetNumber) else { return [] }

        return setState.activeLiberoAssignments.values
            .compactMap { rosterState.playerByID($0) }
            .sorted { $0.displayName < $1.displayName }
    }

    var designatedLiberoSlots: [DesignatedLiberoSlotDisplay] {
        rosterState.designatedLiberoSlots
            .sorted { $0.slotNumber < $1.slotNumber }
            .map {
                DesignatedLiberoSlotDisplay(
                    slotNumber: $0.slotNumber,
                    player: $0.playerID.flatMap { rosterState.playerByID($0) }
                )
            }
    }

    var courtSlotsForCurrentSet: [CourtSlotDisplay] {
        guard let setState = inGameState.stateForSet(gameState.currentSetNumber) else {
            return (1...6).map {
                CourtSlotDisplay(courtPosition: $0, truePlayer: nil, effectivePlayer: nil, liberoPlayer: nil)
            }
        }

        return (1...6).map { courtPosition in
            let truePlayer = setState.truePlayerID(atCourtPosition: courtPosition).flatMap { rosterState.playerByID($0) }
            let effectivePlayer = setState.effectivePlayerID(atCourtPosition: courtPosition).flatMap { rosterState.playerByID($0) }
            let liberoPlayer = setState.activeLiberoPlayerID(atCourtPosition: courtPosition).flatMap { rosterState.playerByID($0) }

            return CourtSlotDisplay(
                courtPosition: courtPosition,
                truePlayer: truePlayer,
                effectivePlayer: effectivePlayer,
                liberoPlayer: liberoPlayer
            )
        }
    }

    var activeRosterPlayers: [Player] {
        rosterState.players
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.jerseyNumber == rhs.jerseyNumber {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.jerseyNumber < rhs.jerseyNumber
            }
    }

    var designatedLiberoPlayerIDs: Set<UUID> {
        Set(rosterState.designatedLiberoSlots.compactMap(\.playerID))
    }

    var availableDesignatedLiberoPlayers: [Player] {
        let designatedIDs = Set(rosterState.designatedLiberoSlots.compactMap(\.playerID))
        return activeRosterPlayers.filter { designatedIDs.contains($0.id) }
    }

    var eventsForCurrentSet: [RallyEvent] {
        gameState.events
            .filter { $0.setNumber == gameState.currentSetNumber }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var reviewQueueForCurrentSet: [CommandInput] {
        commandQueue
            .filter { $0.setNumber == gameState.currentSetNumber && $0.status == .needsReview }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var failedQueueForCurrentSet: [CommandInput] {
        commandQueue
            .filter { $0.setNumber == gameState.currentSetNumber && $0.status == .failed }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func startNewMatch(matchName: String = "", ourTeamName: String = "", opponentName: String = "") {
        let session = Self.makeSession(
            matchName: matchName,
            ourTeamName: ourTeamName,
            opponentName: opponentName,
            rosterTemplate: rosterTemplateForNewMatch()
        )
        appState.matches.append(session)
        appState.activeMatchID = session.id
        loadSession(session, preserveCommands: false)
        Task { await persistState() }
    }

    func switchToMatch(_ id: UUID) {
        guard let session = appState.matches.first(where: { $0.id == id }) else { return }
        appState.activeMatchID = id
        loadSession(session, preserveCommands: false)
        Task { await persistState() }
    }

    /// Updates the name and team labels for any match by ID (active or historical).
    func updateMatchInfo(id: UUID, matchName: String, ourTeamName: String, opponentName: String) {
        guard let index = appState.matches.firstIndex(where: { $0.id == id }) else { return }
        appState.matches[index].match.matchName    = matchName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.matches[index].match.ourTeamName  = ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.matches[index].match.opponentName = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.matches[index].updatedAt = Date()
        Task { await persistState() }
    }

    func updateActiveMatch(opponentName: String) {
        guard var session = activeSession else { return }
        session.match.opponentName = opponentName
        session.updatedAt = Date()
        replaceSession(session)
        loadSession(session, preserveCommands: true)
        Task { await persistState() }
    }

    func sendTextCommand() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        inputText = ""
        await captureAndParseCommand(text: trimmed, source: .text)
    }
    func retryCommand(_ id: UUID) async {
        guard let index = commandQueue.firstIndex(where: { $0.id == id }) else { return }
        let rawText = commandQueue[index].rawText

        commandQueue[index].status = .captured
        commandQueue[index].errorMessage = nil
        commandQueue[index].parsedEvent = nil

        await parseExistingCommand(at: index, rawText: rawText)
    }

    func deleteEvent(id: UUID) {
        gameState.apply(.deleteEvent(id))
        writeBackActiveSession()
        Task { await persistState() }
    }

    func removeCommand(id: UUID) {
        guard let index = commandQueue.firstIndex(where: { $0.id == id }) else { return }
        let command = commandQueue.remove(at: index)

        if let linkedEvent = gameState.events.first(where: { $0.commandID == command.id }) {
            gameState.apply(.deleteEvent(linkedEvent.id))
        }

        writeBackActiveSession()
        Task { await persistState() }
    }

    /// Confirms a `needsReview` command's parsed event and commits it to the game state.
    /// The backend already produced a parse — the user is just signing off on it.
    func acceptPendingReview(commandID: UUID) {
        guard let index = commandQueue.firstIndex(where: { $0.id == commandID }) else { return }
        guard commandQueue[index].status == .needsReview,
              let parsed = commandQueue[index].parsedEvent else { return }
        commitParsedEvent(parsed, forCommandAt: index)
        Task { await persistState() }
    }

    /// True when there is at least one command whose event has been (or could be) committed.
    var canUndoLastCommand: Bool {
        commandQueue.contains {
            $0.status == .committed || $0.status == .needsReview || $0.status == .accepted
        }
    }

    /// Removes the most recently issued live command and its linked event.
    /// Tap repeatedly to peel off multiple commands.
    func undoLastCommand() {
        guard let last = commandQueue.reversed().first(where: {
            $0.status == .committed || $0.status == .needsReview || $0.status == .accepted
        }) else { return }
        removeCommand(id: last.id)
    }

    func reparseAndReplaceEvent(id: UUID, newRawText: String) async {
        let trimmed = newRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
            Task { await persistState() }
        }

        do {
            let backendEvent = try await backend.parseText(
                trimmed,
                setNumber: gameState.currentSetNumber,
                teamID: gameState.teamID,
                matchID: gameState.matchID
            )
            let newEvent = RallyEvent.fromBackend(
                backendEvent,
                teamID: gameState.teamID,
                matchID: gameState.matchID,
                setNumber: gameState.currentSetNumber
            )
            gameState.apply(.replaceEvent(id, with: newEvent))
            writeBackActiveSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeMatch() {
        guard let idx = appState.matches.firstIndex(where: { $0.id == appState.activeMatchID }) else { return }
        appState.matches[idx].match.completedAt = Date()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func startNewSet() {
        gameState.apply(.startNewSet)
        inGameState.ensureSet(matchID: gameState.matchID, setNumber: gameState.currentSetNumber)
        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func savePlayer(_ player: Player) {
        rosterState.upsertPlayer(player)
        rosterState.ensureMatchRosterEntries(
            for: gameState.matchID,
            availablePlayerIDs: rosterState.players.filter(\.isActive).map(\.id)
        )
        writeBackActiveSession()
        Task { await persistState() }
    }

    func setCurrentRotationNumber(_ rotationNumber: Int) throws {
        try inGameState.setCurrentRotationNumber(
            matchID: gameState.matchID,
            setNumber: gameState.currentSetNumber,
            rotationNumber: rotationNumber
        )
        syncRosterStateWithCurrentSet()
        Task { await persistState() }
    }

    func setDesignatedLibero(
        _ playerID: UUID?,
        for slotNumber: Int
    ) {
        let previousPlayerID = rosterState.designatedLiberoSlots
            .first(where: { $0.slotNumber == slotNumber })?
            .playerID

        rosterState.setDesignatedLibero(playerID, for: slotNumber)

        if let previousPlayerID,
           !rosterState.designatedLiberoSlots.contains(where: { $0.playerID == previousPlayerID }) {
            inGameState.removeLiberoPlayer(matchID: gameState.matchID, playerID: previousPlayerID)
            syncRosterStateWithCurrentSet()
        }

        writeBackActiveSession()
        Task { await persistState() }
    }

    func rotateCurrentSetClockwise() throws {
        try inGameState.rotateClockwise(
            matchID: gameState.matchID,
            setNumber: gameState.currentSetNumber
        )
        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func setPlayer(
        _ playerID: UUID?,
        forCourtPosition courtPosition: Int
    ) throws {
        try inGameState.setPlayer(
            matchID: gameState.matchID,
            setNumber: gameState.currentSetNumber,
            playerID: playerID,
            forCourtPosition: courtPosition
        )
        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func substitutePlayer(
        inCourtPosition courtPosition: Int,
        with playerInID: UUID,
        allowOverride: Bool = false
    ) throws {
        if designatedLiberoPlayerIDs.contains(playerInID) {
            throw SubstitutionError.playerInUnavailable(playerID: playerInID)
        }

        guard let setState = inGameState.stateForSet(gameState.currentSetNumber) else {
            throw SubstitutionError.setNotInitialized(setNumber: gameState.currentSetNumber)
        }

        let rotationIndex = setState.rotationSlot(forCourtPosition: courtPosition)

        if let playerOutID = setState.truePlayerID(atCourtPosition: courtPosition) {
            try inGameState.applySubstitution(
                matchID: gameState.matchID,
                setNumber: gameState.currentSetNumber,
                playerInID: playerInID,
                playerOutID: playerOutID,
                rotationIndex: rotationIndex,
                allowOverride: allowOverride
            )
        } else {
            try inGameState.setPlayer(
                matchID: gameState.matchID,
                setNumber: gameState.currentSetNumber,
                playerID: playerInID,
                forCourtPosition: courtPosition
            )
        }

        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func setLibero(
        _ liberoPlayerID: UUID?,
        forCourtPosition courtPosition: Int
    ) throws {
        try inGameState.setLibero(
            matchID: gameState.matchID,
            setNumber: gameState.currentSetNumber,
            liberoPlayerID: liberoPlayerID,
            forCourtPosition: courtPosition
        )
        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func removeLibero(fromCourtPosition courtPosition: Int) throws {
        try setLibero(nil, forCourtPosition: courtPosition)
    }

    func deletePlayer(_ playerID: UUID) {
        inGameState.removePlayer(matchID: gameState.matchID, playerID: playerID)
        rosterState.removePlayer(playerID)
        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func configureStartingLineupForCurrentSet(_ lineupByRotation: [Int: UUID]) throws {
        try inGameState.configureStartingLineup(
            matchID: gameState.matchID,
            setNumber: gameState.currentSetNumber,
            lineupByRotation: lineupByRotation
        )
        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func applySubstitution(
        playerInID: UUID,
        playerOutID: UUID,
        rotationIndex: Int,
        allowOverride: Bool = false
    ) throws {
        try inGameState.applySubstitution(
            matchID: gameState.matchID,
            setNumber: gameState.currentSetNumber,
            playerInID: playerInID,
            playerOutID: playerOutID,
            rotationIndex: rotationIndex,
            allowOverride: allowOverride
        )
        syncRosterStateWithCurrentSet()
        writeBackActiveSession()
        Task { await persistState() }
    }

    func overrideSubstitutionMessage(
        playerInID: UUID,
        playerOutID: UUID
    ) -> String {
        let incomingName = rosterState.playerByID(playerInID)?.displayName ?? "this player"
        let outgoingName = rosterState.playerByID(playerOutID)?.displayName ?? "this player"

        let priorStarterID = inGameState.previousStarterForSub(
            setNumber: gameState.currentSetNumber,
            playerID: playerInID
        )
        let priorStarterName = priorStarterID
            .flatMap { rosterState.playerByID($0)?.displayName }
            ?? "another player"

        return "Are you sure you want to override and sub \(incomingName) for \(outgoingName)? \(incomingName) already substituted for \(priorStarterName) this set."
    }

    func manualScore(us: Int, them: Int) {
        gameState.apply(.manualScore(us: us, them: them))
        writeBackActiveSession()
        Task { await persistState() }
    }

    func adjustScore(team: TeamSide, delta: Int) {
        guard delta != 0 else { return }

        let newUs = max(0, score.us + (team == .us ? delta : 0))
        let newThem = max(0, score.them + (team == .them ? delta : 0))
        manualScore(us: newUs, them: newThem)
    }

    private func captureAndParseCommand(text: String, source: CommandSource) async {
        let command = CommandInput(
            id: UUID(),
            createdAt: Date(),
            teamID: gameState.teamID,
            matchID: gameState.matchID,
            source: source,
            setNumber: gameState.currentSetNumber,
            rawText: text,
            status: .captured,
            parsedEvent: nil,
            errorMessage: nil
        )

        commandQueue.append(command)
        guard let index = commandQueue.indices.last else { return }

        await parseExistingCommand(at: index, rawText: text)
    }

    private func parseExistingCommand(at index: Int, rawText: String) async {
        guard commandQueue.indices.contains(index) else { return }

        isLoading = true
        errorMessage = nil
        commandQueue[index].status = .parsing

        defer {
            isLoading = false
            Task { await persistState() }
        }

        do {
            let setNumber = commandQueue[index].setNumber
            let parsed = try await backend.parseText(
                rawText,
                setNumber: setNumber,
                teamID: commandQueue[index].teamID,
                matchID: commandQueue[index].matchID
            )
            commandQueue[index].parsedEvent = parsed
            commandQueue[index].errorMessage = nil

            if parsed.needsReview {
                commandQueue[index].status = .needsReview
            } else {
                commandQueue[index].status = .accepted
                commitParsedEvent(parsed, forCommandAt: index)
            }
        } catch {
            commandQueue[index].status = .failed
            commandQueue[index].errorMessage = error.localizedDescription
            self.errorMessage = error.localizedDescription
        }
    }

    private func commitParsedEvent(_ parsed: BackendParsedEvent, forCommandAt index: Int) {
        guard commandQueue.indices.contains(index) else { return }

        let command = commandQueue[index]
        let resolvedPlayerID = parsed.playerId
            ?? parsed.playerNumber.flatMap { rosterState.playerByJerseyNumber($0)?.id }

        let event = RallyEvent.fromBackend(
            parsed,
            teamID: command.teamID,
            matchID: command.matchID,
            setNumber: command.setNumber,
            playerID: resolvedPlayerID,
            commandID: command.id
        )

        gameState.apply(.addEvent(event))
        commandQueue[index].status = .committed
        writeBackActiveSession()
    }

    private func restoreState() async {
        do {
            if let restored = try await stateStore.load() {
                appState = restored.appState
            }

            if appState.matches.isEmpty {
                let session = Self.makeSession()
                appState = AppState(activeMatchID: session.id, matches: [session])
            }

            let session = activeSession
                ?? appState.matches.first
                ?? Self.makeSession()

            if appState.activeMatchID == nil {
                appState.activeMatchID = session.id
            }

            loadSession(session, preserveCommands: false)
        } catch {
            errorMessage = "Failed to restore local state: \(error.localizedDescription)"
        }
    }

    private func persistState() async {
        do {
            let state = PersistedAppState(appState: appState)
            try await stateStore.save(state)
        } catch {
            errorMessage = "Failed to save local state: \(error.localizedDescription)"
        }
    }

    private func syncRosterStateWithCurrentSet() {
        guard let setState = inGameState.stateForSet(gameState.currentSetNumber) else { return }

        rosterState.syncCurrentSetState(
            matchID: gameState.matchID,
            setNumber: gameState.currentSetNumber,
            rotationSlotAssignments: setState.rotationSlotAssignments,
            activeLiberoAssignments: setState.activeLiberoAssignments,
            playerStatesByID: setState.playerStates
        )
        writeBackActiveSession()
    }

    private var activeSession: MatchSession? {
        guard let activeMatchID = appState.activeMatchID else { return nil }
        return appState.matches.first(where: { $0.id == activeMatchID })
    }

    private func loadSession(_ session: MatchSession, preserveCommands: Bool) {
        gameState = session.gameState
        inGameState = session.inGameState
        rosterState = session.rosterState
        inGameState.ensureSet(matchID: gameState.matchID, setNumber: gameState.currentSetNumber)
        syncRosterStateWithCurrentSet()

        if !preserveCommands {
            commandQueue = []
        }
    }

    private func writeBackActiveSession() {
        guard var session = activeSession else { return }
        session.gameState = gameState
        session.rosterState = rosterState
        session.inGameState = inGameState
        session.updatedAt = Date()
        replaceSession(session)
    }

    private func replaceSession(_ session: MatchSession) {
        if let index = appState.matches.firstIndex(where: { $0.id == session.id }) {
            appState.matches[index] = session
        } else {
            appState.matches.append(session)
        }
        appState.activeMatchID = session.id
    }

    private func rosterTemplateForNewMatch() -> RosterState {
        RosterState(
            players: rosterState.players,
            matchRosterEntries: [],
            lineupSlots: [],
            playerMatchStates: [],
            designatedLiberoSlots: [
                DesignatedLiberoSlot(slotNumber: 1, playerID: nil),
                DesignatedLiberoSlot(slotNumber: 2, playerID: nil)
            ]
        )
    }

    @MainActor private static func makeSession(
        matchName: String = "",
        ourTeamName: String = "",
        opponentName: String = "",
        rosterTemplate: RosterState = RosterState()
    ) -> MatchSession {
        let teamID = UUID()
        let matchID = UUID()
        let match = Match(
            id: matchID,
            teamID: teamID,
            matchName: matchName,
            ourTeamName: ourTeamName,
            opponentName: opponentName,
            startedAt: Date()
        )
        let gameState = GameState(teamID: teamID, matchID: matchID)
        var inGameState = InGameState()
        inGameState.ensureSet(matchID: matchID, setNumber: gameState.currentSetNumber)

        return MatchSession(
            id: matchID,
            match: match,
            gameState: gameState,
            rosterState: rosterTemplate,
            inGameState: inGameState,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

