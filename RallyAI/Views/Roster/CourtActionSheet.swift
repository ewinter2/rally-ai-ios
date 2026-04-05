import SwiftUI

struct CourtActionSheet: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Environment(\.dismiss) private var dismiss

    let courtPosition: Int

    @State private var errorMessage: String?
    /// Set when a substitution is blocked only by a rotation lock — allows the user to force override.
    @State private var pendingOverride: PendingOverride?

    private struct PendingOverride {
        let playerID: UUID
        let displayLabel: String   // e.g. "12 • Jane Smith"
    }

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

                        Button { dismiss() } label: {
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
                    substitutionSection

                    // Libero options (back row only)
                    if [1, 5, 6].contains(courtPosition), slot?.truePlayer != nil {
                        liberoSection
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        // Standard lineup error alert
        .alert("Lineup Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        // Rotation-lock override confirmation
        .alert("Override Rotation Lock?", isPresented: Binding(
            get: { pendingOverride != nil },
            set: { if !$0 { pendingOverride = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingOverride = nil }
            Button("Force Sub", role: .destructive) {
                guard let override = pendingOverride else { return }
                pendingOverride = nil
                do {
                    try vm.substitutePlayer(
                        inCourtPosition: courtPosition,
                        with: override.playerID,
                        allowOverride: true
                    )
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            if let override = pendingOverride {
                Text("\(override.displayLabel) is locked to a different rotation from an earlier substitution. Forcing this sub may violate re-entry rules. Proceed anyway?")
            }
        }
    }

    // MARK: - Substitution Section

    private var substitutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let subs = availableSubPlayers()
            if subs.isEmpty {
                Text("No available substitutions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subs) { player in
                    subPlayerRow(player)
                }
            }
        }
    }

    private func subPlayerRow(_ player: Player) -> some View {
        Button {
            performSub(playerID: player.id, displayLabel: "\(player.jerseyNumber) • \(player.displayName)")
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

    // MARK: - Libero Section

    private var liberoSection: some View {
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

    // MARK: - Substitution Logic

    private func performSub(playerID: UUID, displayLabel: String) {
        do {
            try vm.substitutePlayer(inCourtPosition: courtPosition, with: playerID)
            dismiss()
        } catch let subError as SubstitutionError {
            if case .playerLockedToDifferentRotation = subError {
                pendingOverride = PendingOverride(playerID: playerID, displayLabel: displayLabel)
            } else {
                errorMessage = subError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Available Player Helpers

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
