import SwiftUI

struct CourtActionSheet: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Environment(\.dismiss) private var dismiss

    let courtPosition: Int
    @State private var errorMessage: String?

    private var slot: CourtSlotDisplay? {
        vm.courtSlotsForCurrentSet.first(where: { $0.courtPosition == courtPosition })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    HStack(alignment: .top) {
                        Text("Available Substitutions")
                            .font(.title2.weight(.semibold))

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Circle())
                        }
                    }

                    // Current occupant
                    if let currentPlayer = slot?.effectivePlayer {
                        Text("\(currentPlayer.jerseyNumber) • \(currentPlayer.displayName)")
                            .font(.headline)
                    } else {
                        Text("This court position is empty.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Substitution options
                    VStack(alignment: .leading, spacing: 10) {
                        let subs = availableSubPlayers()
                        if subs.isEmpty {
                            Text("No available substitutions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(subs) { player in
                                Button {
                                    do {
                                        try vm.substitutePlayer(inCourtPosition: courtPosition, with: player.id)
                                        dismiss()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                } label: {
                                    HStack {
                                        Text("\(player.jerseyNumber) • \(player.displayName)")
                                            .foregroundStyle(.primary)
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

                    // Libero options (back row only)
                    if [1, 5, 6].contains(courtPosition), slot?.truePlayer != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Available Liberos")
                                .font(.headline)

                            if let activeLibero = slot?.liberoPlayer {
                                Button(role: .destructive) {
                                    do {
                                        try vm.removeLibero(fromCourtPosition: courtPosition)
                                        dismiss()
                                    } catch {
                                        errorMessage = error.localizedDescription
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
                            } else {
                                let liberos = availableLiberos()
                                if liberos.isEmpty {
                                    Text("No available liberos.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(liberos) { player in
                                        Button {
                                            do {
                                                try vm.setLibero(player.id, forCourtPosition: courtPosition)
                                                dismiss()
                                            } catch {
                                                errorMessage = error.localizedDescription
                                            }
                                        } label: {
                                            HStack {
                                                Text("\(player.jerseyNumber) • \(player.displayName)")
                                                    .foregroundStyle(.primary)
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
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Lineup Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    // MARK: - Helpers

    private func availableSubPlayers() -> [Player] {
        let currentTruePlayerID = slot?.truePlayer?.id
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

    private func availableLiberos() -> [Player] {
        let activeLiberoElsewhere = vm.courtSlotsForCurrentSet.contains {
            $0.courtPosition != courtPosition && $0.liberoPlayer != nil
        }
        if activeLiberoElsewhere { return [] }

        let effectiveCourtPlayerIDs = Set(
            vm.courtSlotsForCurrentSet
                .filter { $0.courtPosition != courtPosition }
                .compactMap { $0.effectivePlayer?.id }
        )
        let selectedLiberoIDs = Set(
            vm.courtSlotsForCurrentSet
                .filter { $0.courtPosition != courtPosition }
                .compactMap { $0.liberoPlayer?.id }
        )

        return vm.availableDesignatedLiberoPlayers.filter {
            !selectedLiberoIDs.contains($0.id)
                && !effectiveCourtPlayerIDs.contains($0.id)
        }
    }
}
