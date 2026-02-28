import SwiftUI

struct RosterView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Roster")
                    .font(.title2)
                    .bold()

                Text("Roster page scaffold")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Roster")
        }
    }
}

#Preview {
    RosterView()
}
