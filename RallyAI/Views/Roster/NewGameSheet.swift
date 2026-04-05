import SwiftUI

struct NewGameSheet: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var matchNameDraft  = ""
    @State private var ourTeamDraft    = ""
    @State private var opponentDraft   = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Match Name (optional)", text: $matchNameDraft)
                        .autocorrectionDisabled()
                    TextField("Our Team Name (optional)", text: $ourTeamDraft)
                        .autocorrectionDisabled()
                    TextField("Opponent Name (optional)", text: $opponentDraft)
                        .autocorrectionDisabled()
                } header: {
                    Text("Game Details")
                } footer: {
                    Text("All fields are optional. You can edit these later from Game History.")
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        vm.startNewMatch(
                            matchName: matchNameDraft.trimmingCharacters(in: .whitespaces),
                            ourTeamName: ourTeamDraft.trimmingCharacters(in: .whitespaces),
                            opponentName: opponentDraft.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
