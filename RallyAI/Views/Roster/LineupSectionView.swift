import SwiftUI

struct LineupSectionView: View {
    @EnvironmentObject private var vm: TrackingViewModel

    @State private var selectedCourtPosition: Int?
    @State private var selectedDesignatedLiberoSlotNumber: Int?
    @State private var isMatchListPresented = false
    @State private var isNewGameFormPresented = false
    @State private var lineupErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            lineupHeader
            CourtGridView(selectedCourtPosition: $selectedCourtPosition)
            LiberoRowView(selectedDesignatedLiberoSlotNumber: $selectedDesignatedLiberoSlotNumber)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Match list sheet
        .sheet(isPresented: $isMatchListPresented) {
            MatchListSheet()
        }
        // New game sheet
        .sheet(isPresented: $isNewGameFormPresented) {
            NewGameSheet()
        }
        // Court action sheet (substitution / libero)
        .sheet(
            isPresented: Binding(
                get: { selectedCourtPosition != nil },
                set: { if !$0 { selectedCourtPosition = nil } }
            )
        ) {
            if let pos = selectedCourtPosition {
                CourtActionSheet(courtPosition: pos)
            }
        }
        // Designated libero editor sheet
        .sheet(
            isPresented: Binding(
                get: { selectedDesignatedLiberoSlotNumber != nil },
                set: { if !$0 { selectedDesignatedLiberoSlotNumber = nil } }
            )
        ) {
            if let slotNum = selectedDesignatedLiberoSlotNumber {
                DesignatedLiberoEditorSheet(slotNumber: slotNum)
            }
        }
        // Lineup error alert (rotation / rotate buttons)
        .alert("Lineup Error", isPresented: Binding(
            get: { lineupErrorMessage != nil },
            set: { if !$0 { lineupErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { lineupErrorMessage = nil }
        } message: {
            Text(lineupErrorMessage ?? "Something went wrong.")
        }
    }

    // MARK: - Header

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
                    isNewGameFormPresented = true
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

    // MARK: - Display Helpers

    private var matchTitle: String {
        guard let match = vm.activeMatch else { return "Current Game" }
        let name = match.matchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let us   = match.ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let them = match.opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !us.isEmpty && !them.isEmpty { return "\(us) vs \(them)" }
        if !them.isEmpty { return "vs \(them)" }
        return "Current Game"
    }

    private var matchDateText: String {
        let date = vm.activeMatch?.startedAt ?? Date.now
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var serverText: String {
        guard let server = vm.currentServer else { return "Server: Empty" }
        return "Server: \(server.jerseyNumber) \(server.displayName)"
    }
}
