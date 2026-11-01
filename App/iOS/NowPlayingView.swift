import SonosCore
import SonosDesign
import SwiftUI

struct NowPlayingView: View {
    var session: SonosSession
    var groupId: String?
    var back: () -> Void
    var showGroup: () -> Void

    @State private var position: Double = 0
    @State private var master: Double = 0
    @State private var roomDrafts: [String: Double] = [:]

    private var current: PlayerGroup? {
        if let groupId, let group = session.group(groupId) { return group }
        return session.featuredGroup
    }

    var body: some View {
        Group {
            if let current, let item = current.playback.item {
                content(current, item: item)
            } else {
                SonosColor.espresso.ignoresSafeArea()
            }
        }
    }

    private func content(_ groupModel: PlayerGroup, item: NowPlayingItem) -> some View {
        let names = session.household.displayTitle(for: groupModel)
        return ZStack {
            AlbumWash(palette: item.art)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    nav(names)
                    if !session.peers(in: groupModel.id).isEmpty {
                        SessionStrip(peers: session.peers(in: groupModel.id), fontSize: 11)
                    }
                    AlbumArtView(palette: item.art, size: 234, cornerRadius: 18)
                        .shadow(color: .black.opacity(0.55), radius: 24, y: 16)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SonosColor.hairline.opacity(0.6), lineWidth: 0.5))
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 24, weight: .bold)).tracking(-0.4).lineLimit(1)
                            Text(item.artist).font(.system(size: 18)).foregroundStyle(Color(hex: "e8d4af").opacity(0.78)).lineLimit(1)
                        }
                        Spacer()
                        SourceBadge(source: item.source, prominent: true)
                    }
                    VStack(spacing: 7) {
                        BrassSlider(value: $position, trackHeight: 6, showsKnob: false) { new in
                            Task { await session.perform(.seek(groupId: groupModel.id, positionMillis: Int(new / 100 * Double(groupModel.playback.durationMillis)))) }
                        }
                        HStack {
                            Text(MediaTime.label(millis: groupModel.playback.positionMillis))
                            Spacer()
                            Text(MediaTime.remaining(positionMillis: groupModel.playback.positionMillis, durationMillis: groupModel.playback.durationMillis))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .monospacedDigit()
                    }
                    HStack {
                        modeButton(.shuffle, on: groupModel.playback.playModes.shuffle) { toggleShuffle(groupModel) }
                        Spacer()
                        Button { Task { await session.perform(.skipPrevious(groupId: groupModel.id)) } } label: {
                            SonosSymbol(.previous, size: 30)
                        }.buttonStyle(.plain)
                        Spacer()
                        TransportButton(isPlaying: groupModel.playback.state == .playing, scale: .large) {
                            Task {
                                if groupModel.playback.state == .playing {
                                    await session.perform(.pause(groupId: groupModel.id))
                                } else {
                                    await session.perform(.play(groupId: groupModel.id))
                                }
                            }
                        }
                        Spacer()
                        Button { Task { await session.perform(.skipNext(groupId: groupModel.id)) } } label: {
                            SonosSymbol(.next, size: 30)
                        }.buttonStyle(.plain)
                        Spacer()
                        modeButton(.repeat, on: groupModel.playback.playModes.repeat) { toggleRepeat(groupModel) }
                    }
                    volumeCard(groupModel)
                    HStack {
                        SonosSymbol(.queue, size: 20)
                        Spacer()
                        SonosSymbol(.airplay, size: 20)
                        Spacer()
                        SonosSymbol(.speakerHigh, size: 20)
                    }
                    .foregroundStyle(SonosColor.ivory.opacity(0.8))
                    .padding(.horizontal, 36)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .foregroundStyle(SonosColor.ivory)
            }
        }
        .onAppear { sync(groupModel) }
        .onChange(of: groupModel.volume.value) { _, _ in sync(groupModel) }
        .onChange(of: groupModel.playback.positionMillis) { _, _ in
            position = groupModel.playback.progress * 100
        }
    }

    private func nav(_ names: (lead: String, rest: String?)) -> some View {
        HStack {
            circleButton(.chevron, action: back)
            Spacer()
            Button(action: showGroup) {
                HStack(spacing: 6) {
                    SonosSymbol(.link, size: 13)
                    Text(names.rest == nil ? names.lead : "\(names.lead) \(names.rest ?? "")")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    SonosSymbol(.chevron, size: 12)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(SonosColor.hairline.opacity(0.55), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer()
            circleButton(.more, action: showGroup)
        }
    }

    private func volumeCard(_ groupModel: PlayerGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Group Volume")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(SonosColor.brass)
                Spacer()
                Text("\(Int(master))")
                    .font(.system(size: 13, weight: .bold))
            }
            HStack(spacing: 10) {
                SonosSymbol(.speaker, size: 16)
                BrassSlider(value: $master, trackHeight: 10, knobSize: 24) { new in
                    Task { await session.perform(.setGroupVolume(groupId: groupModel.id, volume: Int(new))) }
                }
                SonosSymbol(.speakerHigh, size: 18)
            }
            Rectangle().fill(SonosColor.hairline.opacity(0.35)).frame(height: 0.5)
            ForEach(groupModel.playerIds, id: \.self) { playerId in
                if let player = session.household.player(id: playerId) {
                    HStack(spacing: 12) {
                        Text(player.name)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)
                        BrassSlider(
                            value: binding(for: player),
                            onCommit: { new in
                                Task { await session.perform(.setPlayerVolume(playerId: player.id, volume: Int(new))) }
                            }
                        )
                        Text("\(Int(roomDrafts[player.id] ?? Double(player.volume.value)))")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                            .opacity(0.85)
                    }
                }
            }
            Button(action: showGroup) {
                HStack(spacing: 6) {
                    SonosSymbol(.plus, size: 16)
                    Text("Add Rooms").font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(SonosColor.brassSoft)
                .background(Color(hex: "c9a24a").opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(SonosColor.hairline.opacity(0.5), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.07, green: 0.04, blue: 0.03).opacity(0.5))
        )
        .brassHairline(radius: 26)
    }

    private func circleButton(_ kind: SonosSymbolKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SonosSymbol(kind, size: 16)
                .frame(width: 34, height: 34)
                .background(Color(red: 1, green: 0.94, blue: 0.84).opacity(0.1), in: Circle())
                .overlay(Circle().stroke(SonosColor.hairline.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func modeButton(_ kind: SonosSymbolKind, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SonosSymbol(kind, size: 20)
                .foregroundStyle(on ? SonosColor.brass : SonosColor.ivory.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private func binding(for player: Player) -> Binding<Double> {
        Binding(
            get: { roomDrafts[player.id] ?? Double(player.volume.value) },
            set: { roomDrafts[player.id] = $0 }
        )
    }

    private func sync(_ groupModel: PlayerGroup) {
        master = Double(groupModel.volume.value)
        position = groupModel.playback.progress * 100
        for id in groupModel.playerIds {
            if roomDrafts[id] == nil, let player = session.household.player(id: id) {
                roomDrafts[id] = Double(player.volume.value)
            }
        }
    }

    private func toggleShuffle(_ groupModel: PlayerGroup) {
        var modes = groupModel.playback.playModes
        modes.shuffle.toggle()
        Task { await session.perform(.setPlayModes(groupId: groupModel.id, modes: modes)) }
    }

    private func toggleRepeat(_ groupModel: PlayerGroup) {
        var modes = groupModel.playback.playModes
        modes.repeat.toggle()
        Task { await session.perform(.setPlayModes(groupId: groupModel.id, modes: modes)) }
    }
}
