import SwiftUI

struct LiberoRowView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @Binding var selectedDesignatedLiberoSlotNumber: Int?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(vm.designatedLiberoSlots) { slot in
                liberoCard(slot: slot)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func liberoCard(slot: DesignatedLiberoSlotDisplay) -> some View {
        Button {
            selectedDesignatedLiberoSlotNumber = slot.slotNumber
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
}
