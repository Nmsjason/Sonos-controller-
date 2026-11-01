import SonosCore
import SonosDesign
import SwiftUI

@main
struct SonosControllerApp: App {
    @State private var session = SonosSession()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .preferredColorScheme(.dark)
                .task { await session.start() }
                .onAppear {
                    #if canImport(WatchConnectivity)
                    WatchPhoneBridge.shared.activate()
                    WatchPhoneBridge.shared.onCommand = { command in
                        Task { @MainActor in
                            await session.perform(command)
                        }
                    }
                    #endif
                }
        }
    }
}
