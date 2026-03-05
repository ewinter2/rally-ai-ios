import SwiftUI

struct RosterView: View {
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    lineupPlaceholder

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
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Roster")
        }
        .sheet(isPresented: $isEditorPresented) {
            editorSheet
        }
    }

    private var lineupPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lineup")
                .font(.title3.weight(.semibold))
            Text("Top half lineup UI coming next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

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
            Text("Positions")
                .frame(width: 120, alignment: .leading)
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

            Text(positionText(for: player))
                .frame(width: 120, alignment: .leading)
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
                    deletePlayer(player.id)
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

    private var editorSheet: some View {
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

                Section("Positions") {
                    ForEach(PlayerPosition.allCases) { position in
                        Toggle(position.displayLabel, isOn: bindingForPosition(position))
                    }
                }
            }
            .navigationTitle(editingPlayerID == nil ? "Add Player" : "Edit Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditorPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDraft()
                        isEditorPresented = false
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }

    private func bindingForPosition(_ position: PlayerPosition) -> Binding<Bool> {
        Binding(
            get: { draft.positions.contains(position) },
            set: { enabled in
                if enabled {
                    draft.positions.insert(position)
                } else {
                    draft.positions.remove(position)
                }
            }
        )
    }

    private func positionText(for player: Player) -> String {
        let list = player.positions.map(\.rawValue).joined(separator: ", ")
        return list.isEmpty ? "-" : list
    }

    private func saveDraft() {
        let player = draft.toPlayer(existingID: editingPlayerID)
        var roster = vm.rosterState

        if let editingPlayerID,
           let index = roster.players.firstIndex(where: { $0.id == editingPlayerID }) {
            roster.players[index] = player
        } else {
            roster.players.append(player)
        }

        vm.rosterState = roster
    }

    private func deletePlayer(_ id: UUID) {
        var roster = vm.rosterState
        roster.players.removeAll { $0.id == id }
        vm.rosterState = roster
    }
}

private struct PlayerDraft {
    var jerseyNumber: Int = 0
    var firstName: String = ""
    var lastName: String = ""
    var displayName: String = ""
    var positions: Set<PlayerPosition> = [.outsideHitter]
    var isActive: Bool = true

    init() {}

    init(player: Player) {
        jerseyNumber = player.jerseyNumber
        firstName = player.firstName
        lastName = player.lastName
        displayName = player.displayName
        positions = Set(player.positions)
        isActive = player.isActive
    }

    var isValid: Bool {
        jerseyNumber > 0 && !resolvedDisplayName.isEmpty && !positions.isEmpty
    }

    var resolvedDisplayName: String {
        let explicit = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }

        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return full
    }

    func toPlayer(existingID: UUID?) -> Player {
        let orderedPositions = positions.sorted { $0.rawValue < $1.rawValue }

        return Player(
            id: existingID ?? UUID(),
            jerseyNumber: jerseyNumber,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: resolvedDisplayName,
            positions: orderedPositions,
            isActive: isActive
        )
    }
}

private extension PlayerPosition {
    var displayLabel: String {
        switch self {
        case .setter: return "Setter (S)"
        case .outsideHitter: return "Outside Hitter (OH)"
        case .middleBlocker: return "Middle Blocker (M)"
        case .opposite: return "Opposite (OPP)"
        case .libero: return "Libero (L)"
        case .defensiveSpecialist: return "Defensive Specialist (DS)"
        }
    }
}

#Preview {
    RosterView()
        .environmentObject(TrackingViewModel())
}
