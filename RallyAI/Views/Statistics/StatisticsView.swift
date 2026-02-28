import SwiftUI

struct StatisticsView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Statistics")
                    .font(.title2)
                    .bold()

                Text("Statistics page scaffold")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistics")
        }
    }
}

#Preview {
    StatisticsView()
}
