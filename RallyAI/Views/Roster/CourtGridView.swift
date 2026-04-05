import SwiftUI

struct CourtGridView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Binding var selectedCourtPosition: Int?

    private let orderedPositions = [4, 3, 2, 5, 6, 1]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(orderedPositions, id: \.self) { position in
                if let slot = vm.courtSlotsForCurrentSet.first(where: { $0.courtPosition == position }) {
                    courtCard(for: slot)
                }
            }
        }
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
                    if slot.isLiberoOverlayActive,
                       let truePlayer = slot.truePlayer,
                       let liberoPlayer = slot.liberoPlayer {
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
}
