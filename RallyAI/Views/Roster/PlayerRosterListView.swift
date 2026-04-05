import SwiftUI

struct PlayerRosterListView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @State private var isEditorPresented = false
    @State private var editingPlayerID: UUID?
    @State private var draft = PlayerDraft()

    private var sortedPlayers: [Player] {
        vm.rosterState.players.sorted { lhs, rhs in
            if lhs.jerseyNumber == rhs.jerseyNumber {
                return lhs.displayName < rhs.displayName
            }
            return lhs.jerseyNumber < rhs.jerseyNumber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Roster")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button {
                    editingPlayerID = nil
                    draft = PlayerDraft()
                    isEditorPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
                }
            }

            rosterTable
        }
        .sheet(isPresented: $isEditorPresented) {
            PlayerEditorSheet(editingPlayerID: editingPlayerID, initialDraft: draft)
        }
    }

    // MARK: - Table

    private var rosterTable: some View {
        VStack(spacing: 0) {
            tableHeader

            if sortedPlayers.isEmpty {
                Text("No players yet. Tap + to add players.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .foregroundStyle(.secondary)
                    .background(Color(.secondarySystemGroupedBackground))
            } else {
                ForEach(sortedPlayers) { player in
                    row(for: player)
                    Divider()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("No.")
                .frame(width: 44, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("")
                .frame(width: 96, alignment: .center)
        }
        .font(.subheadline.weight(.semibold))
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private func row(for player: Player) -> some View {
        HStack(spacing: 8) {
            Text("\(player.jerseyNumber)")
                .frame(width: 44, alignment: .leading)

            Text(player.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button("Edit") {
                    editingPlayerID = player.id
                    draft = PlayerDraft(player: player)
                    isEditorPresented = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    vm.deletePlayer(player.id)
                } label: {
                    Image(systemName: "trash")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
    }
}
