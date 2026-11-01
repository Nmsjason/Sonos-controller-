import SonosCore

#if canImport(SwiftUI)
import SwiftUI

public struct PaletteCard<Content: View>: View {
    var palette: ArtPalette
    var radius: CGFloat
    var content: Content

    public init(palette: ArtPalette, radius: CGFloat = 26, @ViewBuilder content: () -> Content) {
        self.palette = palette
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: palette.primary), Color(hex: palette.secondary)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(hex: palette.accent).opacity(0.28))
                .frame(width: 160, height: 160)
                .blur(radius: 24)
                .offset(x: 180, y: -50)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .brassHairline(radius: radius)
        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
    }
}

public struct FeaturedGroupCard: View {
    var groupName: (lead: String, rest: String?)
    var track: String
    var artist: String
    var art: ArtPalette
    var source: MusicSource
    var memberCount: Int
    var volume: Int
    var isPlaying: Bool
    var peers: [SessionPeer]
    var onOpen: () -> Void
    var onToggle: () -> Void
    var onVolume: (Int) -> Void

    @State private var draft: Double = 0

    public init(
        groupName: (lead: String, rest: String?),
        track: String,
        artist: String,
        art: ArtPalette,
        source: MusicSource,
        memberCount: Int,
        volume: Int,
        isPlaying: Bool,
        peers: [SessionPeer],
        onOpen: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onVolume: @escaping (Int) -> Void
    ) {
        self.groupName = groupName
        self.track = track
        self.artist = artist
        self.art = art
        self.source = source
        self.memberCount = memberCount
        self.volume = volume
        self.isPlaying = isPlaying
        self.peers = peers
        self.onOpen = onOpen
        self.onToggle = onToggle
        self.onVolume = onVolume
    }

    public var body: some View {
        PaletteCard(palette: art) {
            VStack(alignment: .leading, spacing: 10) {
                if !peers.isEmpty {
                    SessionStrip(peers: peers, fontSize: 10.5)
                }
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        AlbumArtView(palette: art, size: 78, cornerRadius: 14)
                    }
                    .onTapGesture(perform: onOpen)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(groupName.lead)
                                .font(.system(size: 18, weight: .bold))
                            if let rest = groupName.rest {
                                Text(rest)
                                    .font(.system(size: 18, weight: .semibold))
                                    .opacity(0.8)
                            }
                        }
                        .lineLimit(1)
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                SonosSymbol(.link, size: 11)
                                Text("GROUP · \(memberCount)")
                                    .font(.system(size: 11.5, weight: .bold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.28), in: Capsule())
                            .overlay(Capsule().stroke(SonosColor.hairline.opacity(0.45), lineWidth: 0.5))
                            SourceBadge(source: source, prominent: true)
                        }
                        Text(track).font(SonosFont.track).lineLimit(1)
                        Text(artist).font(SonosFont.artist).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
                    }
                    .onTapGesture(perform: onOpen)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    SonosSymbol(.speaker, size: 16).foregroundStyle(SonosColor.ivory.opacity(0.85))
                    BrassSlider(value: $draft, onCommit: { onVolume(Int($0)) })
                    Text("\(Int(draft))")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 22, alignment: .trailing)
                    TransportButton(isPlaying: isPlaying, action: onToggle)
                }
            }
            .padding(14)
            .foregroundStyle(SonosColor.ivory)
        }
        .onAppear { draft = Double(volume) }
        .onChange(of: volume) { _, new in draft = Double(new) }
    }

    }

public struct RoomTile: View {
    var name: String
    var track: String
    var artist: String
    var art: ArtPalette
    var source: MusicSource
    var volume: Int
    var isPlaying: Bool
    var onOpen: () -> Void
    var onToggle: () -> Void
    var onVolume: (Int) -> Void

    @State private var draft: Double = 0

    public init(
        name: String,
        track: String,
        artist: String,
        art: ArtPalette,
        source: MusicSource,
        volume: Int,
        isPlaying: Bool,
        onOpen: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onVolume: @escaping (Int) -> Void
    ) {
        self.name = name
        self.track = track
        self.artist = artist
        self.art = art
        self.source = source
        self.volume = volume
        self.isPlaying = isPlaying
        self.onOpen = onOpen
        self.onToggle = onToggle
        self.onVolume = onVolume
    }

    public var body: some View {
        PaletteCard(palette: art, radius: 26) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    ZStack(alignment: .bottomTrailing) {
                        AlbumArtView(palette: art, size: 40, cornerRadius: 10, showsLabel: false)
                        ArtDot(source: source).offset(x: 4, y: 4)
                    }
                    Spacer()
                    TransportButton(isPlaying: isPlaying, scale: .small, action: onToggle)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(SonosFont.tileRoom).lineLimit(1)
                    Text(track).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(artist).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                HStack(spacing: 6) {
                    SonosSymbol(.speaker, size: 13).foregroundStyle(SonosColor.ivory.opacity(0.85))
                    BrassSlider(value: $draft, trackHeight: 6, knobSize: 16, onCommit: { onVolume(Int($0)) })
                }
                .padding(.top, 4)
            }
            .padding(12)
            .foregroundStyle(SonosColor.ivory)
        }
        .frame(height: 146)
        .onAppear { draft = Double(volume) }
        .onChange(of: volume) { _, new in draft = Double(new) }
    }
}

public struct IdleRoomRow: View {
    var name: String
    var detail: String
    var art: ArtPalette
    var onPlay: () -> Void

    public init(name: String, detail: String, art: ArtPalette, onPlay: @escaping () -> Void) {
        self.name = name
        self.detail = detail
        self.art = art
        self.onPlay = onPlay
    }

    public var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(palette: art, size: 40, cornerRadius: 9, showsLabel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 16, weight: .bold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(SonosColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            TransportButton(isPlaying: false, scale: .small, ghost: true, action: onPlay)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 56)
        .background(
            LinearGradient(colors: [Color(hex: "2a221c"), Color(hex: "1a1512")], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(SonosColor.hairline.opacity(0.4), lineWidth: 0.5))
        .foregroundStyle(SonosColor.ivory)
    }
}
#endif
