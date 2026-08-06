import SwiftUI

struct AppRootView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                DashboardView()
            } else {
                NavigationStack {
                    HomeView()
                }
            }
        }
    }
}
