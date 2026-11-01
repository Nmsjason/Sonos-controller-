import SonosCore
import SonosDesign
import SwiftUI

struct GroupingView: View {
    var session: SonosSession
    var done: () -> Void
    @State private var draft: [String] = []
    @State private var dragging: String?

    var body: some View {
        ZStack {
            groupingBackground
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    partyBanner
                    section("Presets")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(session.household.presets) { preset in
                                presetCard(preset)
                            }
                        }
                    }
                    section("Now Building")
                    buildZone
                    section("Other Rooms")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(others) { player in
                            otherRoom(player)
                        }
                    }
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            VStack {
                Spacer()
                Button {
                    Task { await session.perform(.createGroup(playerIds: draft)) }
                    done()
                } label: {
                    HStack(spacing: 8) {
                        SonosSymbol(.link, size: 16)
                        Text("Group \(draft.count) Rooms")
                            .font(.system(size: 17, weight: .heavy))
                    }
                    .foregroundStyle(SonosColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Brass.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.45), lineWidth: 0.5))
                    .shadow(color: Color(hex: "a06e28").opacity(0.45), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .disabled(draft.count < 2)
                .opacity(draft.count < 2 ? 0.55 : 1)
            }
        }
        .onAppear {
            if draft.isEmpty {
                draft = session.household.preset(id: "downstairs")?.playerIds
                    ?? session.featuredGroup?.playerIds
                    ?? []
            }
        }
        .foregroundStyle(SonosColor.ivory)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("Group Rooms")
                .font(SonosFont.largeTitle)
                .tracking(-0.6)
            Spacer()
            Button("Done", action: done)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SonosColor.brassDeep)
        }
    }

    private var partyBanner: some View {
        HStack(spacing: 14) {
            SonosSymbol(.party, size: 22)
                .foregroundStyle(SonosColor.brassSoft)
                .frame(width: 50, height: 50)
                .background(Color(hex: "2a1a10"), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Party Mode").font(.system(size: 20, weight: .heavy)).tracking(-0.3)
                Text("Every room · in sync").font(.system(size: 13, weight: .semibold)).opacity(0.75)
            }
            Spacer()
            Text("All \(session.household.roomCount)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(SonosColor.brassSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(hex: "1f150e"), in: Capsule())
        }
        .padding(16)
        .foregroundStyle(SonosColor.ink)
        .background(Brass.fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.45), lineWidth: 0.5))
        .shadow(color: Color(hex: "a06e28").opacity(0.4), radius: 16, y: 8)
        .onTapGesture {
            let ids = session.household.players.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
            let coordinator = session.featuredGroup?.coordinatorId
            draft = promote(coordinator, in: ids)
            Task { await session.perform(.partyMode) }
        }
    }

    private var buildZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let art = session.featuredGroup?.playback.item?.art {
                    AlbumArtView(palette: art, size: 44, cornerRadius: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(draftTitle).font(.system(size: 17, weight: .heavy))
                    Text(session.featuredGroup?.playback.item.map { "\($0.title) · \($0.artist)" } ?? "Choose rooms")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(hex: "e8d4af").opacity(0.8))
                        .lineLimit(1)
                }
            }
            FlowChips(draft: draft, names: name(for:), remove: { id in draft.removeAll { $0 == id } })
            HStack(spacing: 6) {
                SonosSymbol(.link, size: 12)
                Text(dragging == nil ? "Tap a room or drag it in · long-press to set as leader" : "Drop to add")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "e8d4af").opacity(0.65))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(hex: "9a5a2c").opacity(0.55), Color(hex: "4e1c1e").opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(SonosColor.hairline.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [7, 5]))
        )
        .dropDestination(for: String.self) { items, _ in
            for id in items where !draft.contains(id) { draft.append(id) }
            dragging = nil
            return true
        }
    }

    private var others: [Player] {
        session.household.players
            .filter { !draft.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func otherRoom(_ player: Player) -> some View {
        let group = session.household.groups.first { $0.playerIds.contains(player.id) }
        return HStack(spacing: 10) {
            AlbumArtView(palette: group?.playback.item?.art ?? .placeholder(for: .other), size: 38, cornerRadius: 9, showsLabel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(group?.playback.item?.title ?? "Paused")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            SonosSymbol(.grip, size: 14).foregroundStyle(SonosColor.hairline.opacity(0.7))
        }
        .padding(10)
        .frame(height: 62)
        .background(
            LinearGradient(colors: [Color(hex: "272019"), Color(hex: "18130f")], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SonosColor.hairline.opacity(0.35), lineWidth: 0.5))
        .opacity(dragging == player.id ? 0.35 : 1)
        .draggable(player.id) {
            HStack {
                Text(player.name).font(.system(size: 15, weight: .bold))
                Text(group?.playback.item?.title ?? "")
                    .font(.system(size: 12))
            }
            .padding(12)
            .background(Color(hex: "20262e"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "c9a24a"), lineWidth: 1.5))
            .rotationEffect(.degrees(-4))
            .onAppear { dragging = player.id }
            .onDisappear { dragging = nil }
        }
        .onTapGesture {
            if !draft.contains(player.id) { draft.append(player.id) }
        }
    }

    private func presetCard(_ preset: GroupPreset) -> some View {
        Button {
            draft = preset.playerIds
            Task { await session.perform(.activatePreset(id: preset.id)) }
        } label: {
            VStack(alignment: .leading) {
                HStack(spacing: -5) {
                    ForEach(0..<min(preset.playerIds.count, 4), id: \.self) { _ in
                        Circle()
                            .stroke(SonosColor.brassDeep, lineWidth: 1.5)
                            .background(Circle().fill(Color.black.opacity(0.25)))
                            .frame(width: 16, height: 16)
                    }
                }
                Spacer()
                Text(preset.name).font(.system(size: 15, weight: .heavy))
                Text(preset.subtitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 132, height: 84, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(hex: preset.primary), Color(hex: preset.secondary)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .brassHairline(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(SonosColor.brass.opacity(0.75))
    }

    private var groupingBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "15110e"), Color(hex: "0c0a09")], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "2a2a1c"), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(hex: "3a1d16"), .clear], center: UnitPoint(x: 0, y: 0.45), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }

    private var draftTitle: String {
        guard let first = draft.first, let name = session.household.player(id: first)?.name else { return "New Group" }
        if draft.count == 1 { return name }
        if draft.count == 2, let other = session.household.player(id: draft[1])?.name { return "\(name) + \(other)" }
        return "\(name) Group"
    }

    private func name(for id: String) -> String { session.household.player(id: id)?.name ?? id }

    private func promote(_ id: String?, in ids: [String]) -> [String] {
        guard let id, let index = ids.firstIndex(of: id) else { return ids }
        var copy = ids
        copy.insert(copy.remove(at: index), at: 0)
        return copy
    }
}

private struct FlowChips: View {
    var draft: [String]
    var names: (String) -> String
    var remove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(draft, id: \.self) { id in
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Brass.fill).frame(width: 20, height: 20)
                        SonosSymbol(.check, size: 11).foregroundStyle(SonosColor.ink)
                    }
                    Text(names(id)).font(.system(size: 14, weight: .bold)).lineLimit(1)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .foregroundStyle(Color(hex: "2a1a12"))
                .background(
                    LinearGradient(colors: [Color(hex: "f6efe2"), Color(hex: "e4d6bc")], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .onTapGesture { remove(id) }
            }
            Text("Drop here")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SonosColor.brassSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SonosColor.hairline.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
        }
    }
}
