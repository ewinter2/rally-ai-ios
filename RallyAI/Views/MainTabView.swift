import SwiftUI

struct MainTabView: View {
    @StateObject private var vm = TrackingViewModel()

    var body: some View {
        TabView {
            TrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "figure.volleyball")
                }

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }

            RosterView()
                .tabItem {
                    Label("Roster", systemImage: "person.3.fill")
                }
        }
        .environmentObject(vm)
    }
}

#Preview {
    MainTabView()
}
