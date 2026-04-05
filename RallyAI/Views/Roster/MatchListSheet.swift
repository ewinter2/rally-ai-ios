import SwiftUI

struct MatchListSheet: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingMatchSession: MatchSession?
    @State private var matchNameDraft     = ""
    @State private var ourTeamNameDraft   = ""
    @State private var opponentNameDraft  = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.savedMatches.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "sportscourt")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                        Text("No saved games yet.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.savedMatches) { session in
                                matchListRow(session)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Game History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { editingMatchSession != nil },
                set: { if !$0 { editingMatchSession = nil } }
            )) {
                if let session = editingMatchSession {
                    matchEditorForm(session)
                }
            }
        }
    }

    // MARK: - Row

    private func matchListRow(_ session: MatchSession) -> some View {
        let isActive = session.id == vm.activeMatchID

        return HStack(alignment: .center, spacing: 12) {
            Button {
                vm.switchToMatch(session.id)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(matchDisplayName(for: session))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isActive ? Color.blue : .primary)
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Text(setScoreText(for: session))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(session.match.startedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                matchNameDraft    = session.match.matchName
                ourTeamNameDraft  = session.match.ourTeamName
                opponentNameDraft = session.match.opponentName
                editingMatchSession = session
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Editor (pushed within same NavigationStack)

    private func matchEditorForm(_ session: MatchSession) -> some View {
        Form {
            Section {
                TextField("e.g. Regionals Game 1", text: $matchNameDraft)
            } header: {
                Text("Match Name")
            } footer: {
                Text("Used as the display name in the game history list.")
            }

            Section("Team Names") {
                HStack {
                    Text("Us")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("Our team name", text: $ourTeamNameDraft)
                }
                HStack {
                    Text("Them")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("Opponent name", text: $opponentNameDraft)
                }
            }
        }
        .navigationTitle("Edit Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    vm.updateMatchInfo(
                        id: session.id,
                        matchName: matchNameDraft,
                        ourTeamName: ourTeamNameDraft,
                        opponentName: opponentNameDraft
                    )
                    editingMatchSession = nil
                }
            }
        }
    }

    // MARK: - Display Helpers

    private func matchDisplayName(for session: MatchSession) -> String {
        let name = session.match.matchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }

        let us   = session.match.ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let them = session.match.opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !us.isEmpty && !them.isEmpty { return "\(us) vs \(them)" }
        if !them.isEmpty { return "vs \(them)" }
        return session.match.startedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func setScoreText(for session: MatchSession) -> String {
        let numSets = session.gameState.currentSetNumber
        let parts = (1...numSets).map { setNum -> String in
            let score = session.gameState.derivedScore(forSet: setNum)
            return "\(score.us)–\(score.them)"
        }
        return parts.joined(separator: "  ·  ")
    }
}
