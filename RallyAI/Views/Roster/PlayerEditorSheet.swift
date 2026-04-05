import SwiftUI

struct PlayerEditorSheet: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Environment(\.dismiss) private var dismiss

    let editingPlayerID: UUID?
    @State private var draft: PlayerDraft

    init(editingPlayerID: UUID?, initialDraft: PlayerDraft) {
        self.editingPlayerID = editingPlayerID
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("First Name", text: $draft.firstName)
                    TextField("Last Name", text: $draft.lastName)
                    TextField("Display Name", text: $draft.displayName)

                    TextField("Jersey Number", value: $draft.jerseyNumber, format: .number)
                        .keyboardType(.numberPad)

                    Toggle("Active", isOn: $draft.isActive)
                }
            }
            .navigationTitle(editingPlayerID == nil ? "Add Player" : "Edit Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.savePlayer(draft.toPlayer(existingID: editingPlayerID))
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }
}
