import SwiftUI

@main
struct SmolGPTFablesApp: App {
    @StateObject private var studio = StudioViewModel()

    var body: some Scene {
        WindowGroup {
            StudioView()
                .environmentObject(studio)
                .task {
                    if !studio.isUITesting {
                        await studio.prepareSelectedModel()
                    }
                }
        }
    }
}
