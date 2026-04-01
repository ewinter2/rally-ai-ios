import SwiftUI

struct RosterView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @State private var isEditorPresented = false
    @State private var editingPlayerID: UUID?
    @State private var draft = PlayerDraft()
    @State private var isMatchListPresented = false
    @State private var isNewGameConfirmationPresented = false
    @State private var selectedCourtPosition: Int?
    @State private var selectedDesignatedLiberoSlotNumber: Int?
    @State private var selectedDesignatedLiberoPlayerID: UUID?
    @State private var lineupErrorMessage: String?

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
                    lineupSection

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
        .sheet(isPresented: $isMatchListPresented) {
            matchListSheet
        }
        .sheet(
            isPresented: Binding(
                get: { selectedCourtPosition != nil },
                set: { presented in
                    if !presented {
                        selectedCourtPosition = nil
                    }
                }
            )
        ) {
            if let selectedCourtPosition {
                courtActionSheet(courtPosition: selectedCourtPosition)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { selectedDesignatedLiberoSlotNumber != nil },
                set: { presented in
                    if !presented {
                        selectedDesignatedLiberoSlotNumber = nil
                    }
                }
            )
        ) {
            if let selectedDesignatedLiberoSlotNumber {
                designatedLiberoEditorSheet(slotNumber: selectedDesignatedLiberoSlotNumber)
            }
        }
        .alert("Lineup Error", isPresented: lineupErrorBinding) {
            Button("OK", role: .cancel) {
                lineupErrorMessage = nil
            }
        } message: {
            Text(lineupErrorMessage ?? "Something went wrong.")
        }
        .alert("Start a new game?", isPresented: $isNewGameConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Yes") {
                vm.startNewMatch()
            }
        } message: {
            Text("Starting a new game will create a clean slate with an empty roster and statistics.")
        }
    }

    private var lineupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            lineupHeader
            courtGrid
            liberoRow
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lineupHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    isMatchListPresented = true
                } label: {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "line.3.horizontal")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text(matchTitle)
                        .font(.title2.weight(.semibold))
                    Text(matchDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isNewGameConfirmationPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .blue.opacity(0.35), radius: 12, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(1...6, id: \.self) { rotation in
                        Button("Row \(rotation)") {
                            do {
                                try vm.setCurrentRotationNumber(rotation)
                            } catch {
                                lineupErrorMessage = error.localizedDescription
                            }
                        }
                    }
                } label: {
                    Text("Row \(vm.currentRotationNumber)")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Button {
                    do {
                        try vm.rotateCurrentSetClockwise()
                    } catch {
                        lineupErrorMessage = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.primary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            Text(serverText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var courtGrid: some View {
        let orderedPositions = [4, 3, 2, 5, 6, 1]

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(orderedPositions, id: \.self) { courtPosition in
                if let slot = vm.courtSlotsForCurrentSet.first(where: { $0.courtPosition == courtPosition }) {
                    courtCard(for: slot)
                }
            }
        }
    }

    private var liberoRow: some View {
        HStack(spacing: 12) {
            ForEach(vm.designatedLiberoSlots) { slot in
                liberoCard(slot: slot)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func courtCard(for slot: CourtSlotDisplay) -> some View {
        Button {
            selectedCourtPosition = slot.courtPosition
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(slot.isLiberoOverlayActive ? Color.blue.opacity(0.68) : Color(.systemBackground))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 3)

                VStack(alignment: .center, spacing: 6) {
                    if slot.isLiberoOverlayActive, let truePlayer = slot.truePlayer, let liberoPlayer = slot.liberoPlayer {
                        Text(truePlayer.displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.primary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("\(truePlayer.jerseyNumber)")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Spacer()

                        HStack(alignment: .bottom) {
                            VStack(alignment: .center, spacing: 2) {
                                Text(liberoPlayer.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Spacer()

                            Text("\(liberoPlayer.jerseyNumber)")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    } else if let player = slot.effectivePlayer {
                        Text(player.displayName)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Spacer()

                        Text("\(player.jerseyNumber)")
                            .font(.system(size: 34, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Spacer()
                        Text("Empty")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                .padding(10)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }

    private func liberoCard(slot: DesignatedLiberoSlotDisplay) -> some View {
        Button {
            selectedDesignatedLiberoSlotNumber = slot.slotNumber
            selectedDesignatedLiberoPlayerID = slot.player?.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let player = slot.player {
                    Text(player.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text("\(player.jerseyNumber)")
                        .font(.system(size: 24, weight: .medium))
                } else {
                    Spacer()
                    Text("Tap to add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 98, height: 74, alignment: .topLeading)
            .padding(8)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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

    private var serverText: String {
        guard let server = vm.currentServer else {
            return "Server: Empty"
        }

        return "Server: \(server.jerseyNumber) \(server.displayName)"
    }

    private var matchTitle: String {
        let opponent = vm.activeMatch?.opponentName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return opponent.isEmpty ? "Current Match" : "vs. \(opponent)"
    }

    private var matchDateText: String {
        let date = vm.activeMatch?.startedAt ?? Date.now
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func availableSubPlayers(for courtPosition: Int) -> [Player] {
        let currentTruePlayerID = vm.courtSlotsForCurrentSet
            .first(where: { $0.courtPosition == courtPosition })?
            .truePlayer?
            .id

        let designatedLiberoIDs = vm.designatedLiberoPlayerIDs
        let selectedIDs = Set(
            vm.courtSlotsForCurrentSet
                .filter { $0.courtPosition != courtPosition }
                .compactMap { $0.truePlayer?.id }
        )

        return vm.activeRosterPlayers.filter {
            !selectedIDs.contains($0.id)
                && $0.id != currentTruePlayerID
                && !designatedLiberoIDs.contains($0.id)
        }
    }

    private func availableLiberos(for courtPosition: Int) -> [Player] {
        let activeLiberoElsewhere = vm.courtSlotsForCurrentSet.contains {
            $0.courtPosition != courtPosition && $0.liberoPlayer != nil
        }
        if activeLiberoElsewhere {
            return []
        }

        let effectiveCourtPlayerIDs = Set(
            vm.courtSlotsForCurrentSet
                .filter { $0.courtPosition != courtPosition }
                .compactMap { $0.effectivePlayer?.id }
        )
        let selectedIDs = Set(
            vm.courtSlotsForCurrentSet
                .filter { $0.courtPosition != courtPosition }
                .compactMap { $0.liberoPlayer?.id }
        )

        return vm.availableDesignatedLiberoPlayers.filter {
            !selectedIDs.contains($0.id)
                && !effectiveCourtPlayerIDs.contains($0.id)
        }
    }

    private func courtActionSheet(courtPosition: Int) -> some View {
        let slot = vm.courtSlotsForCurrentSet.first(where: { $0.courtPosition == courtPosition })

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available Substitutions")
                                .font(.title2.weight(.semibold))
                        }

                        Spacer()

                        Button {
                            selectedCourtPosition = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Circle())
                        }
                    }

                    if let currentPlayer = slot?.effectivePlayer {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(currentPlayer.jerseyNumber) • \(currentPlayer.displayName)")
                                .font(.headline)
                        }
                    } else {
                        Text("This court position is empty.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {

                        if availableSubPlayers(for: courtPosition).isEmpty {
                            Text("No available substitutions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableSubPlayers(for: courtPosition)) { player in
                                Button {
                                    handleSubSelection(player.id, at: courtPosition)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(player.jerseyNumber) • \(player.displayName)")
                                                .foregroundStyle(.primary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if [1, 5, 6].contains(courtPosition), slot?.truePlayer != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Available Liberos")
                                .font(.headline)

                            if let activeLibero = slot?.liberoPlayer {
                                Button(role: .destructive) {
                                    do {
                                        try vm.removeLibero(fromCourtPosition: courtPosition)
                                        selectedCourtPosition = nil
                                    } catch {
                                        lineupErrorMessage = error.localizedDescription
                                    }
                                } label: {
                                    HStack {
                                        Text("Remove \(activeLibero.displayName)")
                                        Spacer()
                                        Image(systemName: "xmark.circle")
                                    }
                                    .padding(12)
                                    .background(Color.red.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            if slot?.liberoPlayer == nil && availableLiberos(for: courtPosition).isEmpty {
                                Text("No available liberos.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if slot?.liberoPlayer == nil {
                                ForEach(availableLiberos(for: courtPosition)) { player in
                                    Button {
                                        do {
                                            try vm.setLibero(player.id, forCourtPosition: courtPosition)
                                            selectedCourtPosition = nil
                                        } catch {
                                            lineupErrorMessage = error.localizedDescription
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(player.jerseyNumber) • \(player.displayName)")
                                                    .foregroundStyle(.primary)
                                            }

                                            Spacer()

                                            Image(systemName: "person.fill.badge.plus")
                                                .foregroundStyle(.blue)
                                        }
                                        .padding(12)
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func designatedLiberoEditorSheet(slotNumber: Int) -> some View {
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("L\(slotNumber)")
                                .font(.title2.weight(.semibold))
                            Text("Choose the player assigned to this libero slot.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            selectedDesignatedLiberoSlotNumber = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Circle())
                        }
                    }

                    if let selectedDesignatedLiberoPlayerID,
                       let currentPlayer = vm.rosterState.playerByID(selectedDesignatedLiberoPlayerID) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Player")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(currentPlayer.jerseyNumber) • \(currentPlayer.displayName)")
                                .font(.headline)
                        }
                    } else {
                        Text("No libero assigned yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Assign Player")
                            .font(.headline)

                        Button {
                            vm.setDesignatedLibero(nil, for: slotNumber)
                            selectedDesignatedLiberoSlotNumber = nil
                        } label: {
                            HStack {
                                Text("Clear Libero Slot")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if availableLiberoCandidates(for: slotNumber).isEmpty {
                            Text("No bench players are available for this libero slot.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableLiberoCandidates(for: slotNumber)) { player in
                                Button {
                                    vm.setDesignatedLibero(player.id, for: slotNumber)
                                    selectedDesignatedLiberoSlotNumber = nil
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(player.jerseyNumber) • \(player.displayName)")
                                                .foregroundStyle(.primary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func availableLiberoCandidates(for slotNumber: Int) -> [Player] {
        let selectedIDs = Set(
            vm.designatedLiberoSlots
                .filter { $0.slotNumber != slotNumber }
                .compactMap { $0.player?.id }
        )
        let onCourtIDs = Set(
            vm.rosterState.playerMatchStates
                .filter(\.isOnCourt)
                .map(\.playerID)
        )

        return vm.activeRosterPlayers.filter {
            (!selectedIDs.contains($0.id) || $0.id == selectedDesignatedLiberoPlayerID)
                && (!onCourtIDs.contains($0.id) || $0.id == selectedDesignatedLiberoPlayerID)
        }
    }

    private func handleSubSelection(_ playerID: UUID, at courtPosition: Int) {
        do {
            try vm.substitutePlayer(inCourtPosition: courtPosition, with: playerID)
            selectedCourtPosition = nil
        } catch {
            lineupErrorMessage = error.localizedDescription
        }
    }

    private var matchListSheet: some View {
        NavigationStack {
            List {
                if vm.savedMatches.isEmpty {
                    Text("No saved matches yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.savedMatches) { session in
                        Button {
                            vm.switchToMatch(session.id)
                            isMatchListPresented = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(matchLabel(for: session))
                                        .foregroundStyle(.primary)
                                    Text(session.match.startedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if session.id == vm.activeMatchID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Past Games")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isMatchListPresented = false
                    }
                }
            }
        }
    }

    private func matchLabel(for session: MatchSession) -> String {
        let opponent = session.match.opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return opponent.isEmpty ? "Match \(session.match.startedAt.formatted(date: .numeric, time: .omitted))" : "vs. \(opponent)"
    }

    private func saveDraft() {
        let player = draft.toPlayer(existingID: editingPlayerID)
        vm.savePlayer(player)
    }

    private func deletePlayer(_ id: UUID) {
        vm.deletePlayer(id)
    }

    private var lineupErrorBinding: Binding<Bool> {
        Binding(
            get: { lineupErrorMessage != nil },
            set: { presented in
                if !presented {
                    lineupErrorMessage = nil
                }
            }
        )
    }
}

private struct PlayerDraft {
    var jerseyNumber: Int = 0
    var firstName: String = ""
    var lastName: String = ""
    var displayName: String = ""
    var isActive: Bool = true

    init() {}

    init(player: Player) {
        jerseyNumber = player.jerseyNumber
        firstName = player.firstName
        lastName = player.lastName
        displayName = player.displayName
        isActive = player.isActive
    }

    var isValid: Bool {
        jerseyNumber > 0 && !resolvedDisplayName.isEmpty
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
        return Player(
            id: existingID ?? UUID(),
            jerseyNumber: jerseyNumber,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: resolvedDisplayName,
            isActive: isActive
        )
    }
}

#Preview {
    RosterView()
        .environmentObject(TrackingViewModel())
}
