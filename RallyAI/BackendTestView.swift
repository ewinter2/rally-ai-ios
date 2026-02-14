//
//  BackendTestView.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/13/26.
//
import SwiftUI

// Temporary control plane UI to test backend calls
struct BackendTestView: View {
    @StateObject private var vm = TrackingViewModel() //holds all the @published variables in TrackingViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Text("RallyAI Backend Test")
                .font(.title2)
                .bold()
            
            TextField("Enter command (ex: 10 dig)", text: $vm.inputText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            Button {
                Task { await vm.sendTextCommand() }
            } label: {
                if vm.isLoading {
                    ProgressView()
                } else {
                    Text("Send to Backend")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoading || vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            if let error = vm.errorMessage {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
            }
            
            if let event = vm.lastEvent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event parsed!!")
                        .font(.headline)
                    
                    Text("""
                        id: \(event.id)
                        createdAt: \(event.createdAt)
                        setNumber: \(event.setNumber)
                        playerNumber: \(event.playerNumber.map(String.init) ?? "nil")
                        event: \(event.action.rawValue)
                        pointAwardedTo: \(event.pointAwardedTo?.rawValue ?? "nil")
                        needReview: \(event.needsReview.description)
                        rawText: \(event.rawText)                        
                        """)
                    .font(.system(.body, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
        }
        .padding()
    }
    
}
