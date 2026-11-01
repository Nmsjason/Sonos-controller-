import SonosCore
import SonosDesign
import SwiftUI

struct BrowseView: View {
    var session: SonosSession
    @Binding var playOnID: String?
    @State private var source: MusicSource = .spotify
    @State private var query = ""
    @State private var selected: Set<String> = ["RINCON_000E0000000101400", "RINCON_000E0000000601400"]

    private var playOnItem: CatalogItem? {
        guard let playOnID else { return nil }
        return session.sections(for: .spotify).flatMap(\.items).first { $0.id == playOnID }
            ?? session.sections(for: source).flatMap(\.items).first { $0.id == playOnID }
    }

    var body: some View {
        ZStack {
            browseBackground
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Browse")
                        .font(SonosFont.largeTitle)
                        .tracking(-0.6)
                    sourceSwitch
                    HStack(spacing: 8) {
                        SonosSymbol(.browse, size: 16)
                        TextField("Artists, songs, podcasts", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(Color(hex: "e8d4af").opacity(query.isEmpty ? 0.55 : 0.95))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Color(red: 1, green: 0.94, blue: 0.84).opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(SonosColor.hairline.opacity(0.3), lineWidth: 0.5))
                    if source == .pandora {
                        Text("Stations saved on Sonos")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SonosColor.muted)
                    }
                    let sections = filteredSections
                    if sections.isEmpty {
                        Text(source == .pandora ? "No Pandora favorites yet." : "Nothing matches.")
                            .foregroundStyle(SonosColor.muted)
                            .padding(.top, 24)
                    }
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.system(size: 21, weight: .bold))
                            .tracking(-0.3)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(section.items) { item in
                                    Button {
                                        playOnID = item.id
                                        source = item.source
                                    } label: {
                                        VStack(alignment: .leading, spacing: 7) {
                                            AlbumArtView(palette: item.art, size: 132, cornerRadius: 12, showsLabel: false)
                                            Text(item.title)
                                                .font(.system(size: 13, weight: .semibold))
                                                .lineLimit(1)
                                                .frame(width: 132, alignment: .leading)
                                            Text(item.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.white.opacity(0.55))
                                                .lineLimit(1)
                                                .frame(width: 132, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .foregroundStyle(SonosColor.ivory)
            }
        }
        .sheet(item: playOnBinding) { item in
            PlayOnSheet(session: session, item: item, selected: $selected) {
                playOnID = nil
            } confirm: {
                Task {
                    await session.perform(.playItem(PlayRequest(playerIds: orderedSelection, item: item)))
                }
                playOnID = nil
            }
            .presentationDetents([.height(560), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(34)
            .presentationBackground(Color(hex: "18130f").opacity(0.96))
        }
    }

    private var playOnBinding: Binding<CatalogItem?> {
        Binding(
            get: { playOnItem },
            set: { playOnID = $0?.id }
        )
    }

    private var filteredSections: [CatalogSection] {
        let base = session.sections(for: source)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.compactMap { section in
            let items = section.items.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
            }
            guard !items.isEmpty else { return nil }
            return CatalogSection(id: section.id, title: section.title, source: section.source, items: items)
        }
    }

    private var orderedSelection: [String] {
        session.household.players.map(\.id).filter { selected.contains($0) }
    }

    private var sourceSwitch: some View {
        HStack(spacing: 0) {
            sourceButton(.spotify)
            sourceButton(.pandora)
        }
        .padding(3)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(SonosColor.hairline.opacity(0.4), lineWidth: 0.5))
    }

    private func sourceButton(_ value: MusicSource) -> some View {
        Button {
            source = value
            query = ""
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(value == .spotify ? (source == .spotify ? Color(hex: "2d3a24") : SonosColor.spotify) : SonosColor.pandora)
                    .frame(width: 8, height: 8)
                Text(value.displayName).font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(source == value ? SonosColor.ink : Color.white.opacity(0.7))
            .background {
                if source == value {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brass.fill)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var browseBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "243326"), Color(hex: "18201a"), Color(hex: "0f0c0a")], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "3a2a1a"), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

private struct PlayOnSheet: View {
    var session: SonosSession
    var item: CatalogItem
    @Binding var selected: Set<String>
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(SonosColor.hairline.opacity(0.5))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            HStack(spacing: 12) {
                AlbumArtView(palette: item.art, size: 54, cornerRadius: 12, showsLabel: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play on…")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(SonosColor.brass.opacity(0.85))
                    Text(item.title).font(.system(size: 19, weight: .heavy)).tracking(-0.3)
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SonosColor.brassSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 1, green: 0.94, blue: 0.84).opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(SonosColor.hairline.opacity(0.5), lineWidth: 0.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quick("All Rooms", prominent: true) {
                        selected = Set(session.household.players.map(\.id))
                    }
                    ForEach(session.household.presets) { preset in
                        quick(preset.name, prominent: false) { selected = Set(preset.playerIds) }
                    }
                }
            }
            .padding(.top, 6)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
                        } label: {
                            HStack(spacing: 12) {
                                if let art = row.art {
                                    AlbumArtView(palette: art, size: 36, cornerRadius: 9, showsLabel: false)
                                } else {
                                    SonosSymbol(.speaker, size: 16)
                                        .foregroundStyle(Color(hex: "c9b48a"))
                                        .frame(width: 36, height: 36)
                                        .background(Color(red: 1, green: 0.94, blue: 0.84).opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.name).font(.system(size: 16, weight: .semibold))
                                    Text(row.detail).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                                }
                                Spacer()
                                ZStack {
                                    if selected.contains(row.id) {
                                        Circle().fill(Brass.fill).frame(width: 26, height: 26)
                                        SonosSymbol(.check, size: 13).foregroundStyle(SonosColor.ink)
                                    } else {
                                        Circle().stroke(SonosColor.hairline.opacity(0.45), lineWidth: 1.5).frame(width: 26, height: 26)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(SonosColor.hairline.opacity(0.18)).frame(height: 0.5)
                        }
                    }
                }
            }
            Button(action: confirm) {
                HStack(spacing: 8) {
                    SonosSymbol(.play, size: 16)
                    Text("Play on \(selected.count) \(selected.count == 1 ? "Room" : "Rooms")")
                        .font(.system(size: 17, weight: .heavy))
                }
                .foregroundStyle(SonosColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Brass.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.5 : 1)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .foregroundStyle(SonosColor.ivory)
    }

    private func quick(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(prominent ? SonosColor.ink : SonosColor.ivory)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if prominent {
                        Capsule().fill(Brass.fill)
                    } else {
                        Capsule().fill(Color(red: 1, green: 0.94, blue: 0.84).opacity(0.07))
                    }
                }
                .overlay {
                    if !prominent {
                        Capsule().stroke(SonosColor.hairline.opacity(0.4), lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var rows: [PlayRow] {
        var seen = Set<String>()
        var result: [PlayRow] = []
        let groups = session.household.groups.sorted {
            ($0.playerIds.count) > ($1.playerIds.count)
        }
        for group in groups {
            let key = group.playerIds.sorted().joined(separator: "+")
            if group.playerIds.count > 1, seen.insert(key).inserted {
                let playing = group.playback.state == .playing
                let title = group.playback.item?.title ?? "Idle"
                result.append(PlayRow(
                    id: group.coordinatorId,
                    memberIds: group.playerIds,
                    name: group.name,
                    detail: playing ? "\(title) · will replace" : title,
                    art: group.playback.item?.art
                ))
            }
        }
        for player in session.household.players.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let group = session.household.groups.first(where: { $0.coordinatorId == player.id && $0.playerIds.count == 1 }) else { continue }
            let title = group.playback.item?.title
            let detail: String
            if group.playback.state == .playing, let title {
                detail = title
            } else {
                detail = "Idle"
            }
            result.append(PlayRow(id: player.id, memberIds: [player.id], name: player.name, detail: detail, art: group.playback.state == .playing ? group.playback.item?.art : nil))
        }
        return result
    }
}

private struct PlayRow: Identifiable {
    var id: String
    var memberIds: [String]
    var name: String
    var detail: String
    var art: ArtPalette?
}

