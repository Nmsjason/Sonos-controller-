import Foundation

public enum QueueEdit: Equatable, Sendable, Codable {
    case append(uri: String)
    case insertNext(uri: String)
    case remove(track: Int)
    case reorder(from: Int, to: Int)
}

public struct PlayRequest: Equatable, Sendable, Codable {
    public var playerIds: [String]
    public var item: CatalogItem

    public init(playerIds: [String], item: CatalogItem) {
        self.playerIds = playerIds
        self.item = item
    }
}

public enum ControllerCommand: Equatable, Sendable, Codable {
    case play(groupId: String)
    case pause(groupId: String)
    case pauseAll
    case skipNext(groupId: String)
    case skipPrevious(groupId: String)
    case seek(groupId: String, positionMillis: Int)
    case setPlayModes(groupId: String, modes: PlayModes)
    case setGroupVolume(groupId: String, volume: Int)
    case setPlayerVolume(playerId: String, volume: Int)
    case setGroupMembers(groupId: String, playerIds: [String])
    case createGroup(playerIds: [String])
    case partyMode
    case activatePreset(id: String)
    case loadFavorite(favoriteId: String, groupId: String)
    case loadSpotifyURI(uri: String, groupId: String, title: String?)
    case loadPandoraFavorite(favoriteId: String, groupId: String)
    case editQueue(groupId: String, edit: QueueEdit)
    case playItem(PlayRequest)

    public var usesLegacyUPnP: Bool {
        switch self {
        case .loadSpotifyURI, .loadPandoraFavorite, .editQueue:
            return true
        case let .playItem(request):
            return request.item.source == .spotify || request.item.source == .pandora
        default:
            return false
        }
    }
}

public enum ControlPath: String, Codable, Equatable, Sendable {
    /// Local WebSocket on port 1443. Same JSON as the cloud Control API.
    case localWebSocket
    /// UPnP/SOAP on port 1400. Queue edits, Spotify URIs, and Pandora favorites only.
    case legacyUPnP
    /// Cloud Control API. Used when the Watch has no reachable iPhone.
    case cloud
    /// Watch command forwarded to the iPhone over WatchConnectivity.
    case phoneRelay
}

public struct ControlContext: Equatable, Sendable {
    public var localSpeakersReachable: Bool
    public var phoneRelayReachable: Bool
    /// True when the caller is the Watch and it should not assume the iPhone is home.
    public var isWatch: Bool

    public init(localSpeakersReachable: Bool, phoneRelayReachable: Bool = false, isWatch: Bool = false) {
        self.localSpeakersReachable = localSpeakersReachable
        self.phoneRelayReachable = phoneRelayReachable
        self.isWatch = isWatch
    }

    public static let phoneOnLAN = ControlContext(localSpeakersReachable: true)
    public static let phoneOffline = ControlContext(localSpeakersReachable: false)
    public static let watchOnPhone = ControlContext(localSpeakersReachable: false, phoneRelayReachable: true, isWatch: true)
    public static let watchAway = ControlContext(localSpeakersReachable: false, phoneRelayReachable: false, isWatch: true)
}

public enum ControlRouter {
    /// Decide which transport carries a command.
    ///
    /// The phone talks to speakers on the LAN: WebSocket first, UPnP only for the legacy cases.
    /// The cloud is not a general fallback. It is the Watch path used when the phone relay is down.
    public static func route(_ command: ControllerCommand, context: ControlContext) -> Result<ControlPath, SonosError> {
        if context.isWatch {
            return context.phoneRelayReachable ? .success(.phoneRelay) : .success(.cloud)
        }
        if command.usesLegacyUPnP {
            return context.localSpeakersReachable ? .success(.legacyUPnP) : .failure(.notConnected)
        }
        return context.localSpeakersReachable ? .success(.localWebSocket) : .failure(.notConnected)
    }
}

public struct SonosMusicServiceAccount: Equatable, Sendable {
    /// Spotify's service id and account serial differ per household. They come from the player's music services list.
    public var spotifySID: Int
    public var spotifySN: Int
    public var flags: Int

    public init(spotifySID: Int = 9, spotifySN: Int = 1, flags: Int = 8224) {
        self.spotifySID = spotifySID
        self.spotifySN = spotifySN
        self.flags = flags
    }
}

public struct SOAPArgument: Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct UPnPAction: Equatable, Sendable {
    public var url: URL
    public var serviceURN: String
    public var action: String
    public var arguments: [SOAPArgument]

    public init(url: URL, serviceURN: String, action: String, arguments: [(String, String)]) {
        self.url = url
        self.serviceURN = serviceURN
        self.action = action
        self.arguments = arguments.map { SOAPArgument(name: $0.0, value: $0.1) }
    }

    public var soapAction: String { "\"\(serviceURN)#\(action)\"" }

    public func soapEnvelope() -> String {
        let args = arguments.map { argument in
            "<\(argument.name)>\(XML.escape(argument.value))</\(argument.name)>"
        }.joined()
        return """
        <?xml version="1.0"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body>\
        <u:\(action) xmlns:u="\(serviceURN)">\(args)</u:\(action)>\
        </s:Body>\
        </s:Envelope>
        """
    }
}

public enum XML {
    public static func escape(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

public struct CloudCall: Equatable, Sendable {
    public var method: String
    public var path: String
    public var body: JSONValue?

    public init(method: String, path: String, body: JSONValue? = nil) {
        self.method = method
        self.path = path
        self.body = body
    }
}

public enum PreparedCall: Equatable, Sendable {
    case webSocket(ControlMessage)
    case upnp(UPnPAction)
    case cloud(CloudCall)
    case phoneRelay(ControllerCommand)
}

public enum SpotifySonosURI {
    public static func sonosURI(from spotifyURI: String, account: SonosMusicServiceAccount) throws -> String {
        let parts = spotifyURI.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "spotify", !parts[2].isEmpty else {
            throw SonosError.invalidURI(spotifyURI)
        }
        let kind = parts[1]
        let id = parts[2]
        let encoded = "spotify%3a\(kind)%3a\(id)"
        return "x-sonos-spotify:\(encoded)?sid=\(account.spotifySID)&flags=\(account.flags)&sn=\(account.spotifySN)"
    }

    public static func didlClass(for spotifyURI: String) -> String {
        if spotifyURI.contains(":playlist:") || spotifyURI.contains(":album:") {
            return "object.container.playlistContainer"
        }
        return "object.item.audioItem.musicTrack"
    }
}
