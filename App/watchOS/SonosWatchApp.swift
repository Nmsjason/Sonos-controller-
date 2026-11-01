import SonosCore
import SonosDesign
import SwiftUI

@main
struct SonosWatchApp: App {
    @State private var session = SonosSession()

    var body: some Scene {
        WindowGroup {
            WatchNowPlayingView(session: session)
                .task {
                    await session.start()
                    #if canImport(WatchConnectivity)
                    WatchPhoneBridge.shared.activate()
                    #endif
                }
        }
    }
}
