import SonosCore

#if canImport(SwiftUI)
import SwiftUI

public struct AlbumArtView: View {
    var palette: ArtPalette
    var size: CGFloat
    var cornerRadius: CGFloat
    var showsLabel: Bool = true

    public init(palette: ArtPalette, size: CGFloat, cornerRadius: CGFloat, showsLabel: Bool = true) {
        self.palette = palette
        self.size = size
        self.cornerRadius = cornerRadius
        self.showsLabel = showsLabel
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            motif
            if showsLabel, let text = label {
                Text(text)
                    .font(.system(size: max(8, size / 12), weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var label: String? {
        if size >= 180 { return palette.label }
        if size >= 64 { return palette.shortLabel }
        return nil
    }

    @ViewBuilder private var motif: some View {
        switch palette.motif {
        case .sun: sun
        case .orb: orb
        case .wave: wave
        case .grid: grid
        case .stripe: stripe
        }
    }

    private var sun: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: palette.primary), Color(hex: palette.secondary)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: palette.accent), Color(hex: palette.accent).opacity(0)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.36))
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(y: size * 0.04)
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: palette.primary).opacity(0.2), Color(hex: palette.secondary)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 1.45, height: size * 0.62)
                .offset(y: size * 0.42)
        }
    }

    private var orb: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: palette.primary), Color(hex: palette.secondary)], startPoint: .top, endPoint: .bottomTrailing)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: palette.accent).opacity(0.9), .clear], center: UnitPoint(x: 0.7, y: 0.2), startRadius: 0, endRadius: size * 0.45))
            Circle()
                .stroke(Color(hex: "e8d4aa").opacity(0.55), lineWidth: max(2, size * 0.045))
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(x: -size * 0.08, y: size * 0.08)
            Circle()
                .fill(Color(hex: palette.accent))
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(x: size * 0.16, y: size * 0.12)
        }
    }

    private var wave: some View {
        Canvas { context, canvas in
            let colors = [Color(hex: palette.primary), Color(hex: palette.secondary), Color(hex: palette.accent)]
            let stripe = canvas.width * 0.22
            context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            context.rotate(by: .degrees(-12))
            context.translateBy(x: -canvas.width, y: -canvas.height)
            var index = 0
            var x: CGFloat = 0
            while x < canvas.width * 3 {
                let rect = CGRect(x: x, y: 0, width: stripe, height: canvas.height * 3)
                context.fill(Path(rect), with: .color(colors[index % colors.count]))
                x += stripe
                index += 1
            }
        }
        .overlay(Color.black.opacity(0.12))
    }

    private var grid: some View {
        ZStack {
            AngularGradient(colors: [Color(hex: palette.primary), Color(hex: palette.secondary), Color(hex: palette.accent), Color(hex: palette.primary)], center: .center, angle: .degrees(45))
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Color(hex: "14100d"))
                .padding(size * 0.22)
            Circle()
                .fill(Color(hex: palette.accent))
                .padding(size * 0.36)
        }
    }

    private var stripe: some View {
        ZStack {
            HStack(spacing: 0) {
                Color(hex: palette.primary)
                Color(hex: palette.secondary)
                Color(hex: palette.accent)
            }
            RadialGradient(colors: [Color.white.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: size * 0.45)
                .blendMode(.softLight)
        }
    }
}

public struct AlbumWash: View {
    var palette: ArtPalette

    public init(palette: ArtPalette) { self.palette = palette }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: palette.primary).opacity(0.95),
                    Color(hex: palette.secondary).opacity(0.92),
                    Color(hex: "211311"),
                    Color(hex: "140d0b"),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color(hex: palette.accent).opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -80, y: -160)
            Circle()
                .fill(Color(hex: palette.secondary).opacity(0.8))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 40, y: 220)
        }
        .ignoresSafeArea()
    }
}
#endif
