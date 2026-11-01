import SonosCore
import SonosDesign
import SwiftUI

struct WatchNowPlayingView: View {
    var session: SonosSession
    @State private var volume: Double = 64

    private var group: PlayerGroup? { session.featuredGroup }
    private var player: Player? {
        guard let id = group?.coordinatorId else { return nil }
        return session.household.player(id: id)
    }

    var body: some View {
        let item = group?.playback.item
        let palette = item?.art ?? .placeholder(for: .spotify)
        ZStack {
            AlbumWash(palette: palette)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(group.map { session.household.watchTitle(for: $0) } ?? "Sonos")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SonosColor.brass)
                        .lineLimit(1)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                    }
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(SonosColor.peerActive)
                        .frame(width: 5, height: 5)
                        .shadow(color: SonosColor.peerActive.opacity(0.8), radius: 2)
                    Text("\(peerCount) connected")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "e8d4af").opacity(0.85))
                }
                HStack(spacing: 8) {
                    AlbumArtView(palette: palette, size: 36, cornerRadius: 8, showsLabel: false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item?.title ?? "Nothing playing")
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        Text(item?.artist ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "e8d4af").opacity(0.78))
                            .lineLimit(1)
                    }
                }
                HStack {
                    Button { skip(-1) } label: { SonosSymbol(.previous, size: 18) }.buttonStyle(.plain)
                    Spacer()
                    TransportButton(isPlaying: group?.playback.state == .playing, scale: .regular) { toggle() }
                        .scaleEffect(0.82)
                    Spacer()
                    Button { skip(1) } label: { SonosSymbol(.next, size: 18) }.buttonStyle(.plain)
                }
                .padding(.trailing, 18)
                HStack(spacing: 6) {
                    SonosSymbol(.speakerHigh, size: 14)
                    Text(player?.name ?? "Volume")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(volume))")
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Color.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().stroke(SonosColor.hairline.opacity(0.55), lineWidth: 0.5))
                .padding(.trailing, 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(SonosColor.ivory)
            VolumeArc(fraction: volume / 100)
                .frame(width: 28)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 18)
                .allowsHitTesting(false)
        }
        .focusable()
        .digitalCrownRotation($volume, from: 0, through: 100, by: 1.0, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear { volume = Double(player?.volume.value ?? 64) }
        .onChange(of: volume) { _, new in
            guard let player else { return }
            Task { await session.perform(.setPlayerVolume(playerId: player.id, volume: Int(new.rounded()))) }
        }
    }

    private var peerCount: Int {
        guard let group else { return session.snapshot.peers.count }
        let peers = session.peers(in: group.id)
        return peers.isEmpty ? session.snapshot.peers.count : peers.count
    }

    private func toggle() {
        guard let group else { return }
        Task {
            if group.playback.state == .playing {
                await session.perform(.pause(groupId: group.id))
            } else {
                await session.perform(.play(groupId: group.id))
            }
            #if canImport(WatchConnectivity)
            let command: ControllerCommand = group.playback.state == .playing
                ? .pause(groupId: group.id)
                : .play(groupId: group.id)
            WatchPhoneBridge.shared.send(command)
            #endif
        }
    }

    private func skip(_ direction: Int) {
        guard let group else { return }
        Task {
            if direction > 0 {
                await session.perform(.skipNext(groupId: group.id))
                #if canImport(WatchConnectivity)
                WatchPhoneBridge.shared.send(.skipNext(groupId: group.id))
                #endif
            } else {
                await session.perform(.skipPrevious(groupId: group.id))
                #if canImport(WatchConnectivity)
                WatchPhoneBridge.shared.send(.skipPrevious(groupId: group.id))
                #endif
            }
        }
    }
}

private struct VolumeArc: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let knobY = height * (1 - fraction)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 8, y: 6))
                    path.addQuadCurve(to: CGPoint(x: 8, y: height - 6), control: CGPoint(x: 26, y: height / 2))
                }
                .stroke(SonosColor.hairline.opacity(0.22), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: 8, y: height - 6))
                    path.addQuadCurve(to: CGPoint(x: 14, y: knobY), control: CGPoint(x: 22, y: (height + knobY) / 2))
                }
                .stroke(Brass.slider, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Circle()
                    .fill(Color(hex: "f3ead8"))
                    .overlay(Circle().stroke(Color(hex: "9c7434"), lineWidth: 1))
                    .frame(width: 11, height: 11)
                    .position(x: 14, y: knobY)
            }
        }
    }
}
