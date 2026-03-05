import SwiftUI

struct MainTabView: View {
    @StateObject private var vm = TrackingViewModel()

    var body: some View {
        TabView {
            TrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "mic")
                }

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "tablecells")
                }

            RosterView()
                .tabItem {
                    Label("Roster", systemImage: "tshirt")
                }
        }
        .environmentObject(vm)
    }
}

#Preview {
    MainTabView()
}
