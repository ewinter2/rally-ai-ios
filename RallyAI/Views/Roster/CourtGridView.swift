import SwiftUI

struct CourtGridView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Binding var selectedCourtPosition: Int?

    // Front row (near net): 4 = left front, 3 = middle front, 2 = right front
    // Back row:             5 = left back,  6 = middle back,  1 = right back
    private let frontRow = [4, 3, 2]
    private let backRow  = [5, 6, 1]

    var body: some View {
        VStack(spacing: 0) {
            netBand
            courtRow(positions: frontRow)
                .padding(8)
            attackLine
            courtRow(positions: backRow)
                .padding(8)
        }
        .background(Color(.systemFill).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Court Elements

    /// Horizontal band representing the net at the top of the court
    private var netBand: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(height: 2.5)
        }
        .frame(height: 20)
    }

    /// Dashed line representing the 3-meter (attack) line
    private var attackLine: some View {
        HStack(spacing: 5) {
            ForEach(0..<12, id: \.self) { _ in
                Rectangle()
                    .fill(Color(.separator).opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1.5)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 6)
    }

    private func courtRow(positions: [Int]) -> some View {
        HStack(spacing: 8) {
            ForEach(positions, id: \.self) { position in
                if let slot = vm.courtSlotsForCurrentSet.first(where: { $0.courtPosition == position }) {
                    courtCard(for: slot)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    // MARK: - Court Card

    private func courtCard(for slot: CourtSlotDisplay) -> some View {
        Button {
            selectedCourtPosition = slot.courtPosition
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(slot.isLiberoOverlayActive ? Color.blue.opacity(0.68) : Color(.systemBackground))

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 2.5)

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
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Spacer()

                        HStack(alignment: .bottom) {
                            Text(liberoPlayer.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Spacer()
                            Text("\(liberoPlayer.jerseyNumber)")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                    } else if let player = slot.effectivePlayer {
                        Text(player.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Spacer()

                        Text("\(player.jerseyNumber)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Spacer()
                        Text("Empty")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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
