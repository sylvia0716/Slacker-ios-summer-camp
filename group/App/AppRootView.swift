import SwiftUI

/// App shell: owns the prototype's shared store and the primary app navigation.
struct AppRootView: View {
    @State private var store = GroupBombModel()
    @State private var tab = AppTab.groups

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { GroupListView(model: store) }
                .tabItem { Label(AppTab.groups.title, systemImage: AppTab.groups.symbol) }
                .tag(AppTab.groups)
            NavigationStack { MyTasksView(model: store) }
                .tabItem { Label(AppTab.myTasks.title, systemImage: AppTab.myTasks.symbol) }
                .tag(AppTab.myTasks)
            NavigationStack { SettingsView(model: store) }
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbol) }
                .tag(AppTab.settings)
        }
        .tint(BombTheme.ink)
    }
}

#Preview { AppRootView() }
