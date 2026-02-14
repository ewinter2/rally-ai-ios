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
    @Published var inputText: String = "12 kill" //change to empty later
    @Published var isLoading: Bool = false //drives UI loading state
    @Published var lastEvent: Event?
    @Published var errorMessage: String? //stores readable message in case of an error
    
    private let backend: BackendClientProtocol
    
    //Keeping setNumber in memory as 1, will later store in Firebase
    private(set) var setNumber: Int = 1
    
    init(backend: BackendClientProtocol = BackendClient()) {
        self.backend = backend
    }
    
    func sendTextCommand() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        lastEvent = nil
        
        do {
            let backendEvent = try await backend.parseText(trimmed, setNumber: setNumber)
            lastEvent = Event.fromBackend(backendEvent, setNumber: setNumber)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

