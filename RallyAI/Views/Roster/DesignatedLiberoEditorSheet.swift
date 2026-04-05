import SwiftUI

struct DesignatedLiberoEditorSheet: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Environment(\.dismiss) private var dismiss

    let slotNumber: Int

    private var currentPlayer: Player? {
        vm.designatedLiberoSlots.first(where: { $0.slotNumber == slotNumber })?.player
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
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

                    // Current assignment
                    if let player = currentPlayer {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Player")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(player.jerseyNumber) • \(player.displayName)")
                                .font(.headline)
                        }
                    } else {
                        Text("No libero assigned yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Assign Player")
                            .font(.headline)

                        Button {
                            vm.setDesignatedLibero(nil, for: slotNumber)
                            dismiss()
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

                        let candidates = availableLiberoCandidates()
                        if candidates.isEmpty {
                            Text("No bench players are available for this libero slot.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(candidates) { player in
                                Button {
                                    vm.setDesignatedLibero(player.id, for: slotNumber)
                                    dismiss()
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
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Helpers

    private func availableLiberoCandidates() -> [Player] {
        let otherSlotIDs = Set(
            vm.designatedLiberoSlots
                .filter { $0.slotNumber != slotNumber }
                .compactMap { $0.player?.id }
        )
        let onCourtIDs = Set(
            vm.rosterState.playerMatchStates
                .filter(\.isOnCourt)
                .map(\.playerID)
        )
        let currentPlayerID = currentPlayer?.id

        return vm.activeRosterPlayers.filter {
            (!otherSlotIDs.contains($0.id) || $0.id == currentPlayerID)
                && (!onCourtIDs.contains($0.id) || $0.id == currentPlayerID)
        }
    }
}
