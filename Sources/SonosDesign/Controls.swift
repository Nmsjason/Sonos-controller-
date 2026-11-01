import SonosCore

#if canImport(SwiftUI)
import SwiftUI

public struct BrassSlider: View {
    @Binding var value: Double
    var trackHeight: CGFloat = 8
    var knobSize: CGFloat = 20
    var showsKnob: Bool = true
    var onCommit: (Double) -> Void = { _ in }

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 8,
        knobSize: CGFloat = 20,
        showsKnob: Bool = true,
        onCommit: @escaping (Double) -> Void = { _ in }
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.knobSize = knobSize
        self.showsKnob = showsKnob
        self.onCommit = onCommit
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = min(1, max(0, value / 100))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.08, green: 0.055, blue: 0.04).opacity(0.38))
                    .frame(height: trackHeight)
                    .overlay(Capsule().stroke(SonosColor.hairline.opacity(0.28), lineWidth: 0.5))
                Capsule()
                    .fill(Brass.slider)
                    .frame(width: max(trackHeight, width * fraction), height: trackHeight)
                if showsKnob {
                    Circle()
                        .fill(Brass.knob)
                        .frame(width: knobSize, height: knobSize)
                        .overlay(Circle().stroke(Color(hex: "966e32").opacity(0.8), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        .offset(x: width * fraction - knobSize / 2)
                }
            }
            .frame(height: max(knobSize, trackHeight))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = min(100, max(0, gesture.location.x / max(width, 1) * 100))
                    }
                    .onEnded { _ in onCommit(value) }
            )
        }
        .frame(height: max(knobSize, trackHeight))
        .accessibilityElement()
        .accessibilityValue("\(Int(value))")
    }
}

public struct TransportButton: View {
    public enum Scale { case large, regular, small }
    var isPlaying: Bool
    var scale: Scale = .regular
    var ghost: Bool = false
    var action: () -> Void

    public init(isPlaying: Bool, scale: Scale = .regular, ghost: Bool = false, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.scale = scale
        self.ghost = ghost
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SonosSymbol(isPlaying ? .pause : .play, size: icon)
                .foregroundStyle(ghost ? SonosColor.brassSoft : Color(hex: "2a1a12"))
                .frame(width: diameter, height: diameter)
                .background {
                    if ghost {
                        Circle().fill(Color(hex: "c9a24a").opacity(0.18))
                        Circle().stroke(SonosColor.hairline.opacity(0.6), lineWidth: 0.5)
                    } else {
                        Circle().fill(Brass.play)
                    }
                }
                .shadow(color: scale == .large ? Color(hex: "c9a24a").opacity(0.35) : .clear, radius: 8)
                .overlay {
                    if scale == .large {
                        Circle().stroke(Color(hex: "c9a24a"), lineWidth: 1)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private var diameter: CGFloat {
        switch scale {
        case .large: return 72
        case .regular: return 44
        case .small: return 36
        }
    }

    private var icon: CGFloat {
        switch scale {
        case .large: return 28
        case .regular: return 18
        case .small: return 15
        }
    }
}

public struct SessionStrip: View {
    var peers: [SessionPeer]
    var fontSize: CGFloat = 11

    public init(peers: [SessionPeer], fontSize: CGFloat = 11) {
        self.peers = peers
        self.fontSize = fontSize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Users joined to session")
                    .font(.system(size: max(9, fontSize - 1.5), weight: .bold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(hex: "f0e1c3").opacity(0.8))
                Text("\(peers.count)")
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(SonosColor.ink)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(Brass.fill, in: Capsule())
            }
            HStack(spacing: 5) {
                ForEach(peers) { peer in
                    HStack(spacing: 4) {
                        SonosSymbol(.phone, size: fontSize)
                        Text(peer.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Circle()
                            .fill(peer.presence == .guest ? SonosColor.peerGuest : SonosColor.peerActive)
                            .frame(width: 6, height: 6)
                            .shadow(color: (peer.presence == .guest ? SonosColor.peerGuest : SonosColor.peerActive).opacity(0.7), radius: 2)
                    }
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(SonosColor.ivory)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.06, green: 0.04, blue: 0.03).opacity(0.38), in: Capsule())
                    .overlay(Capsule().stroke(SonosColor.hairline.opacity(0.4), lineWidth: 0.5))
                }
            }
        }
    }
}

public struct SourceBadge: View {
    var source: MusicSource
    var prominent: Bool = false

    public init(source: MusicSource, prominent: Bool = false) {
        self.source = source
        self.prominent = prominent
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle().fill(sourceColor(source)).frame(width: 8, height: 8)
            if prominent {
                Text(source.displayName)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(SonosColor.ivory)
        .padding(.horizontal, prominent ? 8 : 6)
        .padding(.vertical, prominent ? 4 : 3)
        .background(Color(red: 0.06, green: 0.04, blue: 0.03).opacity(0.35), in: Capsule())
        .overlay(Capsule().stroke(SonosColor.hairline.opacity(0.45), lineWidth: 0.5))
    }
}

public struct GlassChip: View {
    var title: String
    var system: SonosSymbolKind?
    var prominent: Bool = false
    var action: () -> Void

    public init(_ title: String, system: SonosSymbolKind? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.system = system
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let system {
                    SonosSymbol(system, size: prominent ? 16 : 14)
                }
                Text(title)
                    .font(SonosFont.chip)
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? SonosColor.ink : SonosColor.ivory)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                if prominent {
                    Capsule().fill(Brass.fill)
                        .shadow(color: Color(hex: "a06e28").opacity(0.35), radius: 8, y: 4)
                } else {
                    Capsule().fill(Color(red: 1, green: 0.94, blue: 0.84).opacity(0.07))
                }
            }
            .overlay(Capsule().stroke(prominent ? Color.white.opacity(0.35) : SonosColor.hairline.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

public enum SonosTab: String, CaseIterable, Identifiable {
    case rooms, nowPlaying, group, browse
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rooms: return "Rooms"
        case .nowPlaying: return "Now Playing"
        case .group: return "Group"
        case .browse: return "Browse"
        }
    }
    var symbol: SonosSymbolKind {
        switch self {
        case .rooms: return .rooms
        case .nowPlaying: return .nowPlaying
        case .group: return .group
        case .browse: return .browse
        }
    }
}

public struct SonosTabBar: View {
    @Binding var selection: SonosTab

    public init(selection: Binding<SonosTab>) { self._selection = selection }

    public var body: some View {
        HStack {
            ForEach(SonosTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        SonosSymbol(tab.symbol, size: 22)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? SonosColor.brass : SonosColor.tabIdle)
                    .shadow(color: selection == tab ? SonosColor.brass.opacity(0.45) : .clear, radius: 5)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(hex: "14100d").opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(hex: "c9a24a").opacity(0.35)).frame(height: 0.5)
        }
    }
}

public struct ArtDot: View {
    var source: MusicSource
    public init(source: MusicSource) { self.source = source }
    public var body: some View {
        Circle()
            .fill(sourceColor(source))
            .frame(width: 8, height: 8)
            .padding(4)
            .background(Circle().fill(Color(hex: "15100c")))
            .overlay(Circle().stroke(Color(hex: "c9a24a"), lineWidth: 1.5))
    }
}
#endif
