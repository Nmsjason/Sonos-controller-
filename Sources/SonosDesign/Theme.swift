import Foundation
import SonosCore

#if canImport(SwiftUI)
import SwiftUI

public extension Color {
    init(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

public enum SonosColor {
    public static let espresso = Color(hex: "0c0a09")
    public static let charcoal = Color(hex: "14100d")
    public static let smoked = Color(hex: "15110e")
    public static let ivory = Color(hex: "f3ecdf")
    public static let brass = Color(hex: "dcbc78")
    public static let brassDeep = Color(hex: "d9b46c")
    public static let brassSoft = Color(hex: "e6cd8f")
    public static let hairline = Color(hex: "d6b46e")
    public static let ink = Color(hex: "1a120c")
    public static let spotify = Color(hex: "8fae7e")
    public static let pandora = Color(hex: "7d8fa8")
    public static let peerActive = Color(hex: "93c47d")
    public static let peerGuest = Color(hex: "d4ae5e")
    public static let muted = Color.white.opacity(0.62)
    public static let tabIdle = Color(hex: "e8dcc8").opacity(0.42)
}

public enum Brass {
    public static let fill = LinearGradient(
        stops: [
            .init(color: Color(hex: "6e4b22"), location: 0),
            .init(color: Color(hex: "b08443"), location: 0.30),
            .init(color: Color(hex: "e6cd8f"), location: 0.50),
            .init(color: Color(hex: "b8893f"), location: 0.68),
            .init(color: Color(hex: "7a5527"), location: 1),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let slider = LinearGradient(
        colors: [Color(hex: "f0dca6"), Color(hex: "c9a24a"), Color(hex: "9c7434")],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let sheen = LinearGradient(
        stops: [
            .init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0.16), location: 0),
            .init(color: .clear, location: 0.32),
            .init(color: .clear, location: 0.70),
            .init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0.06), location: 1),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let knob = RadialGradient(
        colors: [Color(hex: "fffaf0"), Color(hex: "e9dcc2"), Color(hex: "b9a37a")],
        center: UnitPoint(x: 0.35, y: 0.30),
        startRadius: 0,
        endRadius: 18
    )

    public static let play = RadialGradient(
        colors: [Color(hex: "fffaf0"), Color(hex: "eadfc8"), Color(hex: "c4ad84")],
        center: UnitPoint(x: 0.35, y: 0.30),
        startRadius: 0,
        endRadius: 40
    )
}

public struct BrassHairline: ViewModifier {
    var radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .overlay(Brass.sheen.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SonosColor.hairline.opacity(0.55), lineWidth: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    .mask(
                        LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)
                    )
            )
    }
}

public extension View {
    func brassHairline(radius: CGFloat) -> some View {
        modifier(BrassHairline(radius: radius))
    }
}

public enum SonosFont {
    public static let largeTitle = Font.system(size: 34, weight: .bold)
    public static let room = Font.system(size: 20, weight: .bold)
    public static let tileRoom = Font.system(size: 17, weight: .bold)
    public static let track = Font.system(size: 15, weight: .semibold)
    public static let artist = Font.system(size: 13, weight: .regular)
    public static let chip = Font.system(size: 14, weight: .semibold)
    public static let caption = Font.system(size: 12, weight: .semibold)
    public static let micro = Font.system(size: 11, weight: .bold)
}

public func sourceColor(_ source: MusicSource) -> Color {
    switch source {
    case .spotify: return SonosColor.spotify
    case .pandora: return SonosColor.pandora
    case .other: return SonosColor.brassDeep
    }
}
#endif
