import SwiftUI

@main
struct FrictionBlockerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 620, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
    }
}
