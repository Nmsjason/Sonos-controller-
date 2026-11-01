import SonosCore
import SonosDesign
import SwiftUI

struct RootView: View {
    var session: SonosSession
    @State private var tab: SonosTab = .rooms
    @State private var nowPlayingGroupId: String?
    @State private var playOnID: String? = "late-night"

    var body: some View {
        ZStack {
            SonosColor.espresso.ignoresSafeArea()
            switch tab {
            case .rooms:
                RoomsView(session: session, open: openGroup)
            case .nowPlaying:
                NowPlayingView(session: session, groupId: nowPlayingGroupId, back: { tab = .rooms }, showGroup: { tab = .group })
            case .group:
                GroupingView(session: session, done: { tab = .rooms })
            case .browse:
                BrowseView(session: session, playOnID: $playOnID)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == .rooms || (tab == .browse && playOnID == nil) {
                SonosTabBar(selection: $tab)
            }
        }
    }

    private func openGroup(_ id: String) {
        nowPlayingGroupId = id
        tab = .nowPlaying
    }
}
