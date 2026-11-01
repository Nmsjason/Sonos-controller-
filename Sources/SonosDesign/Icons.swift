#if canImport(SwiftUI)
import SwiftUI

public enum SonosSymbolKind {
    case play, pause, next, previous
    case speaker, speakerHigh
    case rooms, nowPlaying, group, browse
    case link, plus, check, chevron, more
    case shuffle, `repeat`, airplay, queue, grip, party, phone
}

public struct SonosSymbol: View {
    var kind: SonosSymbolKind
    var size: CGFloat = 22

    public init(_ kind: SonosSymbolKind, size: CGFloat = 22) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        icon
            .frame(width: size, height: size)
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .play:
            PlayShape().fill(.foreground)
        case .pause:
            PauseShape().fill(.foreground)
        case .next:
            SkipShape(flipped: false).fill(.foreground)
        case .previous:
            SkipShape(flipped: true).fill(.foreground)
        case .speaker:
            SpeakerShape(waves: 1).stroke(.foreground, style: line)
        case .speakerHigh:
            SpeakerShape(waves: 2).stroke(.foreground, style: line)
        case .rooms:
            RoomsShape().stroke(.foreground, style: line)
        case .nowPlaying:
            NotesShape().stroke(.foreground, style: line)
        case .group:
            GroupShape().stroke(.foreground, style: line)
        case .browse:
            SearchShape().stroke(.foreground, style: line)
        case .link:
            LinkShape().stroke(.foreground, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case .plus:
            PlusShape().stroke(.foreground, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        case .check:
            CheckShape().stroke(.foreground, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        case .chevron:
            ChevronShape().stroke(.foreground, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        case .more:
            MoreShape().fill(.foreground)
        case .shuffle:
            ShuffleShape().stroke(.foreground, style: line)
        case .repeat:
            RepeatShape().stroke(.foreground, style: line)
        case .airplay:
            AirPlayShape().stroke(.foreground, style: line)
        case .queue:
            QueueShape().stroke(.foreground, style: line)
        case .grip:
            GripShape().fill(.foreground)
        case .party:
            PartyShape().fill(.foreground)
        case .phone:
            PhoneShape().stroke(.foreground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private var line: StrokeStyle { StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round) }
}

private struct PlayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.maxY - rect.height * 0.22))
        path.closeSubpath()
        return path
    }
}

private struct PauseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width * 0.16
        let h = rect.height * 0.58
        path.addRoundedRect(in: CGRect(x: rect.midX - w * 1.5, y: rect.midY - h / 2, width: w, height: h), cornerSize: CGSize(width: 2, height: 2))
        path.addRoundedRect(in: CGRect(x: rect.midX + w * 0.5, y: rect.midY - h / 2, width: w, height: h), cornerSize: CGSize(width: 2, height: 2))
        return path
    }
}

private struct SkipShape: Shape {
    var flipped: Bool
    func path(in rect: CGRect) -> Path {
        var path = PlayShape().path(in: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.22))
        let bar = CGRect(x: rect.maxX - rect.width * 0.28, y: rect.minY + rect.height * 0.24, width: rect.width * 0.1, height: rect.height * 0.52)
        path.addRoundedRect(in: bar, cornerSize: CGSize(width: 1, height: 1))
        if flipped {
            return path.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: -1, y: 1).translatedBy(x: -rect.midX, y: -rect.midY))
        }
        return path
    }
}

private struct SpeakerShape: Shape {
    var waves: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.40))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.40))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.40))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.40))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.28))
        path.closeSubpath()
        if waves > 0 {
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.18, startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
        }
        if waves > 1 {
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.30, startAngle: .degrees(-55), endAngle: .degrees(55), clockwise: false)
        }
        return path
    }
}

private struct RoomsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = rect.width * 0.34
        let gap = rect.width * 0.12
        for row in 0..<2 {
            for col in 0..<2 {
                let origin = CGPoint(x: rect.minX + CGFloat(col) * (s + gap), y: rect.minY + CGFloat(row) * (s + gap))
                path.addRoundedRect(in: CGRect(origin: origin, size: CGSize(width: s, height: s)), cornerSize: CGSize(width: 3, height: 3))
            }
        }
        return path
    }
}

private struct NotesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + 2, y: rect.maxY - rect.height * 0.38, width: rect.width * 0.28, height: rect.height * 0.24))
        path.addEllipse(in: CGRect(x: rect.midX + 2, y: rect.maxY - rect.height * 0.48, width: rect.width * 0.28, height: rect.height * 0.24))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.36))
        return path
    }
}

private struct GroupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY + rect.height * 0.18, width: rect.width * 0.62, height: rect.height * 0.64))
        path.addEllipse(in: CGRect(x: rect.maxX - rect.width * 0.62, y: rect.minY + rect.height * 0.18, width: rect.width * 0.62, height: rect.height * 0.64))
        return path
    }
}

private struct SearchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width * 0.62, height: rect.height * 0.62))
        path.move(to: CGPoint(x: rect.midX + 2, y: rect.midY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
        return path
    }
}

private struct LinkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + 2, y: rect.midY - 4, width: rect.width * 0.46, height: 10), cornerSize: CGSize(width: 5, height: 5))
        path.addRoundedRect(in: CGRect(x: rect.midX - 2, y: rect.midY - 6, width: rect.width * 0.46, height: 10), cornerSize: CGSize(width: 5, height: 5))
        return path
    }
}

private struct PlusShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 3))
        path.move(to: CGPoint(x: rect.minX + 3, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.midY))
        return path
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.28))
        return path
    }
}

private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.minY + rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + rect.height * 0.38))
        return path
    }
}

private struct MoreShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<3 {
            let x = rect.minX + rect.width * (0.2 + CGFloat(index) * 0.3)
            path.addEllipse(in: CGRect(x: x, y: rect.midY - 2, width: 4, height: 4))
        }
        return path
    }
}

private struct ShuffleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 4))
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 8))
        return path
    }
}

private struct RepeatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.32, startAngle: .degrees(40), endAngle: .degrees(320), clockwise: false)
        return path
    }
}

private struct AirPlayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + 2, y: rect.minY + 3, width: rect.width - 4, height: rect.height * 0.48), cornerSize: CGSize(width: 3, height: 3))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.midY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.midY + 2))
        path.closeSubpath()
        return path
    }
}

private struct QueueShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<3 {
            let y = rect.minY + 5 + CGFloat(index) * 6
            path.move(to: CGPoint(x: rect.minX + 2, y: y))
            path.addLine(to: CGPoint(x: rect.midX + 2, y: y))
        }
        path.move(to: CGPoint(x: rect.midX + 4, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.midY + 4))
        path.addLine(to: CGPoint(x: rect.midX + 4, y: rect.maxY - 4))
        path.closeSubpath()
        return path
    }
}

private struct GripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for row in 0..<3 {
            for col in 0..<2 {
                let x = rect.minX + 4 + CGFloat(col) * 7
                let y = rect.minY + 3 + CGFloat(row) * 6
                path.addEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
            }
        }
        return path
    }
}

private struct PartyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 3, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct PhoneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect.insetBy(dx: rect.width * 0.28, dy: 1), cornerSize: CGSize(width: 3, height: 3))
        path.addRoundedRect(in: CGRect(x: rect.midX - 3, y: rect.minY + 3, width: 6, height: 2), cornerSize: CGSize(width: 1, height: 1))
        return path
    }
}
#endif
