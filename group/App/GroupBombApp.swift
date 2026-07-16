import SwiftUI

/// Application entry point. It deliberately only wires the root view.
@main
struct GroupBombApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
