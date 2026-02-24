//
//  BackendTestView.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/13/26.
//
import SwiftUI

// Temporary control plane UI to test backend calls
struct BackendTestView: View {
    @StateObject private var vm = TrackingViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("RallyAI Backend Test")
                .font(.title2)
                .bold()

            VStack(spacing: 4) {
                Text("Set \(vm.currentSetNumber)")
                    .font(.headline)

                Text("Score: \(vm.score.us) - \(vm.score.them)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

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

            Button("Start New Set") {
                vm.startNewSet()
            }
            .buttonStyle(.bordered)

            if let error = vm.errorMessage {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Command Review Queue")
                    .font(.headline)

                if vm.reviewQueueForCurrentSet.isEmpty {
                    Text("No commands needing review.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(vm.reviewQueueForCurrentSet) { command in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.rawText)
                                    .font(.body)
                                Text(command.status.rawValue.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.orange)

                                if let parsed = command.parsedEvent {
                                    Text("Parsed: P: \(parsed.playerNumber.map(String.init) ?? "nil") • \(parsed.event) • Point: \(parsed.pointAwardedTo ?? "nil")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Button("Accept + Commit") {
                                    vm.acceptReviewedCommand(command.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                    }
                    .frame(height: 170)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Failed Commands")
                    .font(.headline)

                if vm.failedQueueForCurrentSet.isEmpty {
                    Text("No failed commands.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(vm.failedQueueForCurrentSet) { command in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.rawText)
                                    .font(.body)

                                if let error = command.errorMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                Button("Retry") {
                                    Task { await vm.retryCommand(command.id) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(vm.isLoading)
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Events (Current Set)")
                    .font(.headline)

                if vm.eventsForCurrentSet.isEmpty {
                    Text("No events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(vm.eventsForCurrentSet) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.rawText)
                                    .foregroundStyle(event.needsReview ? .red : .primary)

                                Text("P: \(event.playerNumber.map(String.init) ?? "nil") • \(event.action.rawValue) • Point: \(event.pointAwardedTo?.rawValue ?? "nil")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    vm.deleteEvent(id: event.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }

            Spacer()
        }
        .padding()
    }
}
