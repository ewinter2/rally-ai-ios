import SwiftUI

struct RosterView: View {
    @EnvironmentObject private var vm: TrackingViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LineupSectionView()
                    PlayerRosterListView()
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Roster")
        }
    }
}

#Preview {
    RosterView()
        .environmentObject(TrackingViewModel())
}
