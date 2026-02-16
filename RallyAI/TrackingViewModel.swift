//
//  TrackingViewModel.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/12/26.
//
import Foundation
import Combine

@MainActor //ensures any changes to @published properties happen safely on the main thread
final class TrackingViewModel: ObservableObject { //ensures swift auto refreshes
    @Published var inputText: String = "" //change to empty later
    @Published var isLoading: Bool = false //drives UI loading state
    @Published var errorMessage: String? //stores readable message in case of an error
    
    @Published private(set) var gameState: GameState = GameState()
    
    private let backend: BackendClientProtocol
    
    //Keeping setNumber in memory as 1, will later store in Firebase
    private(set) var setNumber: Int = 1
    
    init(backend: BackendClientProtocol = BackendClient()) {
        self.backend = backend
    }
    
    var currentSetNumber: Int { gameState.currentSetNumber }
    var score: Score { gameState.score }
    
    var eventsForCurrentSet: [RallyEvent] {
        gameState.events
            .filter { $0.setNumber == gameState.currentSetNumber }
            .sorted {$0.createdAt < $1.createdAt }
    }
    
    func sendTextCommand() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let backendEvent = try await backend.parseText(trimmed, setNumber: gameState.currentSetNumber)
            let event = RallyEvent.fromBackend(backendEvent, setNumber: gameState.currentSetNumber)
            gameState.apply(.addEvent(event))
            inputText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func deleteEvent(id: UUID) {
        gameState.apply(.deleteEvent(id))
    }
    
    func reparseAndReplaceEvent(id: UUID, newRawText: String) async {
        let trimmed = newRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let backendEvent = try await backend.parseText(trimmed, setNumber: gameState.currentSetNumber)
            let newEvent = RallyEvent.fromBackend(backendEvent, setNumber: gameState.currentSetNumber, id: id)
            gameState.apply(.replaceEvent(id, with: newEvent))
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func startNewSet() {
        gameState.apply(.startNewSet)
    }
    
    func manualScore(us: Int, them: Int) {
        gameState.apply(.manualScore(us: us, them: them))
    }
}

