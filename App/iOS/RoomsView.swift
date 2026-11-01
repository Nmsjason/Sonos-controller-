import SonosCore
import SonosDesign
import SwiftUI

struct RoomsView: View {
    var session: SonosSession
    var open: (String) -> Void

    private var household: Household { session.household }
    private var featured: PlayerGroup? { household.featuredGroup }

    private var tiles: [PlayerGroup] {
        household.groups
            .filter { $0.id != featured?.id && $0.playback.state == .playing }
            .sorted { sort($0, $1) }
    }

    private var resting: [PlayerGroup] {
        household.groups
            .filter { $0.playback.state != .playing }
            .sorted { sort($0, $1) }
    }

    var body: some View {
        ZStack {
            roomsBackground
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    quickActions
                    if let featured, let art = featured.playback.item?.art {
                        FeaturedGroupCard(
                            groupName: household.displayTitle(for: featured),
                            track: featured.playback.item?.title ?? "Nothing playing",
                            artist: featured.playback.item?.artist ?? "",
                            art: art,
                            source: featured.playback.item?.source ?? .other,
                            memberCount: featured.playerIds.count,
                            volume: featured.volume.value,
                            isPlaying: featured.playback.state == .playing,
                            peers: session.peers(in: featured.id),
                            onOpen: { open(featured.id) },
                            onToggle: { toggle(featured) },
                            onVolume: { volume in
                                Task { await session.perform(.setGroupVolume(groupId: featured.id, volume: volume)) }
                            }
                        )
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(tiles) { group in
                            tile(group)
                        }
                    }
                    ForEach(resting) { group in
                        IdleRoomRow(
                            name: group.name,
                            detail: idleDetail(group),
                            art: group.playback.item?.art ?? .placeholder(for: .other),
                            onPlay: { Task { await session.perform(.play(groupId: group.id)) } }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .bottom) {
                Text("Home")
                    .font(SonosFont.largeTitle)
                    .tracking(-0.6)
                Spacer()
                Text(session.profile.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SonosColor.ink)
                    .frame(width: 34, height: 34)
                    .background(Brass.fill, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 0.5))
            }
            Text(household.summaryLine)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SonosColor.muted)
        }
        .foregroundStyle(SonosColor.ivory)
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            GlassChip("Party Mode", system: .party, prominent: true) {
                Task { await session.perform(.partyMode) }
            }
            GlassChip("Pause All", system: .pause) {
                Task { await session.perform(.pauseAll) }
            }
            GlassChip("Downstairs") {
                Task { await session.perform(.activatePreset(id: "downstairs")) }
            }
        }
    }

    private var roomsBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "15110e"), Color(hex: "0c0a09")], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "3a2518"), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Color(hex: "1d2a22"), .clear], center: UnitPoint(x: 1, y: 0.28), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private func tile(_ group: PlayerGroup) -> some View {
        let player = household.player(id: group.coordinatorId)
        RoomTile(
            name: group.name,
            track: group.playback.item?.title ?? "",
            artist: group.playback.item?.artist ?? "",
            art: group.playback.item?.art ?? .placeholder(for: .other),
            source: group.playback.item?.source ?? .other,
            volume: player?.volume.value ?? group.volume.value,
            isPlaying: group.playback.state == .playing,
            onOpen: { open(group.id) },
            onToggle: { toggle(group) },
            onVolume: { volume in
                if let player {
                    Task { await session.perform(.setPlayerVolume(playerId: player.id, volume: volume)) }
                }
            }
        )
    }

    private func toggle(_ group: PlayerGroup) {
        Task {
            if group.playback.state == .playing {
                await session.perform(.pause(groupId: group.id))
            } else {
                await session.perform(.play(groupId: group.id))
            }
        }
    }

    private func idleDetail(_ group: PlayerGroup) -> String {
        let state = group.playback.state == .paused ? "Paused" : "Idle"
        guard let item = group.playback.item else { return state }
        return "\(state) · \(item.title) — \(item.artist)"
    }

    private func sort(_ lhs: PlayerGroup, _ rhs: PlayerGroup) -> Bool {
        let left = household.player(id: lhs.coordinatorId)?.sortOrder ?? 0
        let right = household.player(id: rhs.coordinatorId)?.sortOrder ?? 0
        return left < right
    }
}
