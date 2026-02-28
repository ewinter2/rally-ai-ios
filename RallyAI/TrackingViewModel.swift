//
//  TrackingViewModel.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/12/26.
//
import Foundation
import Combine

@MainActor
final class TrackingViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published private(set) var gameState: GameState = GameState()
    @Published private(set) var commandQueue: [CommandInput] = []

    private let backend: BackendClientProtocol
    private let stateStore: LocalStateStoreProtocol

    init(
        backend: BackendClientProtocol? = nil,
        stateStore: LocalStateStoreProtocol? = nil,
        restoreOnInit: Bool = true
    ) {
        self.backend = backend ?? BackendClient()
        self.stateStore = stateStore ?? LocalStateStore()

        if restoreOnInit {
            Task { await restoreState() }
        }
    }

    var currentSetNumber: Int { gameState.currentSetNumber }
    var score: Score { gameState.score }

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

    func sendTextCommand() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        inputText = ""
        await captureAndParseCommand(text: trimmed, source: .text)
    }

    func acceptReviewedCommand(_ id: UUID) {
        guard let index = commandQueue.firstIndex(where: { $0.id == id }) else { return }
        guard let parsed = commandQueue[index].parsedEvent else { return }

        commandQueue[index].status = .accepted
        commitParsedEvent(parsed, forCommandAt: index)
        Task { await persistState() }
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
        Task { await persistState() }
    }

    func removeCommand(id: UUID) {
        guard let index = commandQueue.firstIndex(where: { $0.id == id }) else { return }
        let command = commandQueue.remove(at: index)

        if let linkedEvent = gameState.events.first(where: { $0.commandID == command.id }) {
            gameState.apply(.deleteEvent(linkedEvent.id))
        }

        Task { await persistState() }
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
            let backendEvent = try await backend.parseText(trimmed, setNumber: gameState.currentSetNumber)
            let newEvent = RallyEvent.fromBackend(backendEvent, setNumber: gameState.currentSetNumber)
            gameState.apply(.replaceEvent(id, with: newEvent))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startNewSet() {
        gameState.apply(.startNewSet)
        Task { await persistState() }
    }

    func manualScore(us: Int, them: Int) {
        gameState.apply(.manualScore(us: us, them: them))
        Task { await persistState() }
    }

    private func captureAndParseCommand(text: String, source: CommandSource) async {
        let command = CommandInput(
            id: UUID(),
            createdAt: Date(),
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
            let parsed = try await backend.parseText(rawText, setNumber: setNumber)
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
        let event = RallyEvent.fromBackend(
            parsed,
            setNumber: command.setNumber,
            commandID: command.id
        )

        gameState.apply(.addEvent(event))
        commandQueue[index].status = .committed
    }

    private func restoreState() async {
        do {
            if let restored = try await stateStore.load() {
                gameState = restored.gameState
                commandQueue = restored.commandQueue
            }
        } catch {
            errorMessage = "Failed to restore local state: \(error.localizedDescription)"
        }
    }

    private func persistState() async {
        do {
            let state = PersistedAppState(gameState: gameState, commandQueue: commandQueue)
            try await stateStore.save(state)
        } catch {
            errorMessage = "Failed to save local state: \(error.localizedDescription)"
        }
    }
}
