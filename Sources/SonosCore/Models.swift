import Foundation

// MARK: - Identifiers and shared enums

public enum MusicSource: String, Codable, Equatable, Sendable, CaseIterable {
    case spotify
    case pandora
    case other

    public var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .pandora: return "Pandora"
        case .other: return "Line-in"
        }
    }
}

public enum ArtMotif: String, Codable, Equatable, Sendable {
    case sun, orb, wave, grid, stripe
}

public struct ArtPalette: Codable, Equatable, Sendable {
    public var primary: String
    public var secondary: String
    public var accent: String
    public var motif: ArtMotif
    public var label: String?
    public var shortLabel: String?

    public init(
        primary: String,
        secondary: String,
        accent: String,
        motif: ArtMotif,
        label: String? = nil,
        shortLabel: String? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
        self.motif = motif
        self.label = label
        self.shortLabel = shortLabel
    }

    public static func placeholder(for source: MusicSource) -> ArtPalette {
        switch source {
        case .spotify:
            return ArtPalette(primary: "6e4b22", secondary: "2a1a12", accent: "e6cd8f", motif: .sun)
        case .pandora:
            return ArtPalette(primary: "3d4a5c", secondary: "1c2128", accent: "7d8fa8", motif: .orb)
        case .other:
            return ArtPalette(primary: "2a221c", secondary: "14100d", accent: "c9a24a", motif: .stripe)
        }
    }
}

public struct Volume: Codable, Equatable, Sendable {
    public var value: Int
    public var muted: Bool

    public init(value: Int, muted: Bool = false) {
        self.value = min(100, max(0, value))
        self.muted = muted
    }
}

public enum PlaybackState: String, Codable, Equatable, Sendable {
    case playing
    case paused
    case idle
    case buffering

    public var isPlaying: Bool { self == .playing }

    public static func fromSonos(_ raw: String) -> PlaybackState? {
        switch raw {
        case "PLAYBACK_STATE_PLAYING": return .playing
        case "PLAYBACK_STATE_PAUSED": return .paused
        case "PLAYBACK_STATE_IDLE": return .idle
        case "PLAYBACK_STATE_BUFFERING": return .buffering
        default: return nil
        }
    }

    public var sonosRaw: String {
        switch self {
        case .playing: return "PLAYBACK_STATE_PLAYING"
        case .paused: return "PLAYBACK_STATE_PAUSED"
        case .idle: return "PLAYBACK_STATE_IDLE"
        case .buffering: return "PLAYBACK_STATE_BUFFERING"
        }
    }
}

public struct PlayModes: Codable, Equatable, Sendable {
    public var shuffle: Bool
    public var `repeat`: Bool
    public var repeatOne: Bool
    public var crossfade: Bool

    public init(shuffle: Bool = false, repeat: Bool = false, repeatOne: Bool = false, crossfade: Bool = false) {
        self.shuffle = shuffle
        self.repeat = `repeat`
        self.repeatOne = repeatOne
        self.crossfade = crossfade
    }
}

public struct NowPlayingItem: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var source: MusicSource
    public var art: ArtPalette
    public var spotifyURI: String?

    public init(
        title: String,
        artist: String,
        album: String,
        source: MusicSource,
        art: ArtPalette,
        spotifyURI: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.art = art
        self.spotifyURI = spotifyURI
    }
}

public struct Playback: Codable, Equatable, Sendable {
    public var state: PlaybackState
    public var positionMillis: Int
    public var durationMillis: Int
    public var item: NowPlayingItem?
    public var playModes: PlayModes

    public init(
        state: PlaybackState,
        positionMillis: Int = 0,
        durationMillis: Int = 0,
        item: NowPlayingItem? = nil,
        playModes: PlayModes = PlayModes()
    ) {
        self.state = state
        self.positionMillis = max(0, positionMillis)
        self.durationMillis = max(0, durationMillis)
        self.item = item
        self.playModes = playModes
    }

    public static let idle = Playback(state: .idle)

    public var progress: Double {
        guard durationMillis > 0 else { return 0 }
        return min(1, max(0, Double(positionMillis) / Double(durationMillis)))
    }
}

public enum MediaTime {
    /// `1:24`. Hours are included only past 60 minutes.
    public static func label(millis: Int) -> String {
        let total = max(0, millis) / 1000
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// `−2:18`, using the minus glyph from the approved now-playing screen.
    public static func remaining(positionMillis: Int, durationMillis: Int) -> String {
        let left = max(0, durationMillis - max(0, positionMillis))
        return "−" + label(millis: left)
    }
}

public struct Player: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var volume: Volume
    public var host: String?
    public var sortOrder: Int

    public init(id: String, name: String, volume: Volume, host: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.volume = volume
        self.host = host
        self.sortOrder = sortOrder
    }
}

public struct PlayerGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var coordinatorId: String
    public var playerIds: [String]
    public var volume: Volume
    public var playback: Playback

    public init(
        id: String,
        name: String,
        coordinatorId: String,
        playerIds: [String],
        volume: Volume,
        playback: Playback
    ) {
        self.id = id
        self.name = name
        self.coordinatorId = coordinatorId
        self.playerIds = playerIds
        self.volume = volume
        self.playback = playback
    }

    public var isMultiRoom: Bool { playerIds.count > 1 }
}

public struct GroupPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var playerIds: [String]
    public var subtitle: String
    public var primary: String
    public var secondary: String

    public init(
        id: String,
        name: String,
        playerIds: [String],
        subtitle: String,
        primary: String,
        secondary: String
    ) {
        self.id = id
        self.name = name
        self.playerIds = playerIds
        self.subtitle = subtitle
        self.primary = primary
        self.secondary = secondary
    }
}

public enum FavoriteKind: String, Codable, Equatable, Sendable {
    case playlist, album, station, track
}

public struct Favorite: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var source: MusicSource
    public var kind: FavoriteKind
    public var art: ArtPalette
    /// Sonos URI already stored on the household. Pandora playback uses this and nothing else.
    public var sonosURI: String?
    public var spotifyURI: String?

    public init(
        id: String,
        name: String,
        subtitle: String,
        source: MusicSource,
        kind: FavoriteKind,
        art: ArtPalette,
        sonosURI: String? = nil,
        spotifyURI: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.source = source
        self.kind = kind
        self.art = art
        self.sonosURI = sonosURI
        self.spotifyURI = spotifyURI
    }
}

public enum PeerPresence: String, Codable, Equatable, Sendable {
    /// This phone is actively controlling the group.
    case active
    /// A guest handoff, drawn with a brass dot instead of sage.
    case guest
}

public struct SessionPeer: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var groupId: String?
    public var presence: PeerPresence

    public init(id: String, name: String, groupId: String? = nil, presence: PeerPresence = .active) {
        self.id = id
        self.name = name
        self.groupId = groupId
        self.presence = presence
    }
}

public struct Household: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var players: [Player]
    public var groups: [PlayerGroup]
    public var presets: [GroupPreset]
    public var favorites: [Favorite]

    public init(
        id: String,
        name: String,
        players: [Player],
        groups: [PlayerGroup],
        presets: [GroupPreset],
        favorites: [Favorite]
    ) {
        self.id = id
        self.name = name
        self.players = players
        self.groups = groups
        self.presets = presets
        self.favorites = favorites
    }

    public func player(id: String) -> Player? {
        players.first { $0.id == id }
    }

    public func group(id: String) -> PlayerGroup? {
        groups.first { $0.id == id }
    }

    public func preset(id: String) -> GroupPreset? {
        presets.first { $0.id == id }
    }

    public func favorite(id: String) -> Favorite? {
        favorites.first { $0.id == id }
    }

    public var roomCount: Int { players.count }

    public var playingZoneCount: Int {
        groups.filter { $0.playback.state == .playing }.count
    }

    public var multiRoomGroupCount: Int {
        groups.filter(\.isMultiRoom).count
    }

    /// "5 rooms playing · 1 group · 7 rooms"
    public var summaryLine: String {
        HouseholdSummary.line(
            playingZones: playingZoneCount,
            multiRoomGroups: multiRoomGroupCount,
            rooms: roomCount
        )
    }

    public var featuredGroup: PlayerGroup? {
        groups.sorted { lhs, rhs in
            if lhs.playerIds.count != rhs.playerIds.count {
                return lhs.playerIds.count > rhs.playerIds.count
            }
            let left = player(id: lhs.coordinatorId)?.sortOrder ?? 0
            let right = player(id: rhs.coordinatorId)?.sortOrder ?? 0
            return left < right
        }.first
    }

    public func memberNames(for group: PlayerGroup) -> [String] {
        group.playerIds.map { player(id: $0)?.name ?? $0 }
    }

    public func watchTitle(for group: PlayerGroup) -> String {
        let names = memberNames(for: group)
        guard let first = names.first else { return group.name }
        let extra = names.count - 1
        if extra <= 0 { return first }
        return "\(first) +\(extra)"
    }

    public func displayTitle(for group: PlayerGroup) -> (lead: String, rest: String?) {
        let names = memberNames(for: group)
        guard let first = names.first else { return (group.name, nil) }
        if names.count == 2 { return (first, "+ \(names[1])") }
        if names.count > 2 { return (first, "+ \(names.count - 1)") }
        return (first, nil)
    }
}

public enum HouseholdSummary {
    public static func line(playingZones: Int, multiRoomGroups: Int, rooms: Int) -> String {
        let zoneWord = playingZones == 1 ? "room" : "rooms"
        let groupWord = multiRoomGroups == 1 ? "group" : "groups"
        let roomWord = rooms == 1 ? "room" : "rooms"
        return "\(playingZones) \(zoneWord) playing · \(multiRoomGroups) \(groupWord) · \(rooms) \(roomWord)"
    }
}

public enum CatalogKind: String, Codable, Equatable, Sendable {
    case playlist, album, station, track, mix
}

public struct CatalogItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var source: MusicSource
    public var kind: CatalogKind
    public var art: ArtPalette
    public var spotifyURI: String?
    public var favoriteId: String?

    public init(
        id: String,
        title: String,
        subtitle: String,
        source: MusicSource,
        kind: CatalogKind,
        art: ArtPalette,
        spotifyURI: String? = nil,
        favoriteId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.kind = kind
        self.art = art
        self.spotifyURI = spotifyURI
        self.favoriteId = favoriteId
    }
}

public struct CatalogSection: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var source: MusicSource
    public var items: [CatalogItem]

    public init(id: String, title: String, source: MusicSource, items: [CatalogItem]) {
        self.id = id
        self.title = title
        self.source = source
        self.items = items
    }
}

public struct Profile: Codable, Equatable, Sendable {
    public var name: String
    public var initials: String

    public init(name: String, initials: String) {
        self.name = name
        self.initials = initials
    }
}

public enum DiscoverySource: String, Codable, Equatable, Sendable {
    case bonjour
    case ssdp
}

public struct DiscoveredSpeaker: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public var householdId: String?
    public var host: String
    public var websocketPort: Int
    public var location: URL?
    public var source: DiscoverySource

    public init(
        id: String,
        name: String?,
        householdId: String?,
        host: String,
        websocketPort: Int = 1443,
        location: URL? = nil,
        source: DiscoverySource
    ) {
        self.id = id
        self.name = name
        self.householdId = householdId
        self.host = host
        self.websocketPort = websocketPort
        self.location = location
        self.source = source
    }

    public var websocketURL: URL {
        URL(string: "wss://\(host):\(websocketPort)/websocket/api")!
    }
}

public struct DiscoveryState: Codable, Equatable, Sendable {
    public var speakers: [DiscoveredSpeaker]
    public var usedSSDPFallback: Bool

    public init(speakers: [DiscoveredSpeaker] = [], usedSSDPFallback: Bool = false) {
        self.speakers = speakers
        self.usedSSDPFallback = usedSSDPFallback
    }
}

public struct HouseholdSnapshot: Codable, Equatable, Sendable {
    public var household: Household
    public var peers: [SessionPeer]
    public var catalog: [CatalogSection]
    public var profile: Profile
    public var discovery: DiscoveryState

    public init(
        household: Household,
        peers: [SessionPeer],
        catalog: [CatalogSection],
        profile: Profile,
        discovery: DiscoveryState = DiscoveryState()
    ) {
        self.household = household
        self.peers = peers
        self.catalog = catalog
        self.profile = profile
        self.discovery = discovery
    }

    public func peers(in groupId: String) -> [SessionPeer] {
        peers.filter { $0.groupId == groupId }
    }

    public func sections(for source: MusicSource) -> [CatalogSection] {
        if source == .pandora {
            return pandoraSectionsFromFavorites()
        }
        return catalog.filter { $0.source == source }
    }

    /// Pandora in this app is the stations already saved as Sonos favorites. There is no Pandora browse API.
    public func pandoraSectionsFromFavorites() -> [CatalogSection] {
        let items = household.favorites.filter { $0.source == .pandora }.map { favorite in
            CatalogItem(
                id: favorite.id,
                title: favorite.name,
                subtitle: favorite.subtitle,
                source: .pandora,
                kind: .station,
                art: favorite.art,
                favoriteId: favorite.id
            )
        }
        guard !items.isEmpty else { return [] }
        return [CatalogSection(id: "pandora-favorites", title: "Your Stations", source: .pandora, items: items)]
    }
}

public enum SonosError: Error, Equatable, Sendable, LocalizedError {
    case notConnected
    case speakerUnreachable
    case pandoraLimitedToFavorites
    case cloudUnavailable
    case invalidURI(String)
    case soapFault(String)
    case commandFailed(String)
    case malformed(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No Sonos speaker is reachable on this network."
        case .speakerUnreachable:
            return "The group coordinator did not answer."
        case .pandoraLimitedToFavorites:
            return "Pandora playback is limited to stations saved as Sonos favorites."
        case .cloudUnavailable:
            return "The Sonos cloud Control API is only used when the Watch is away from the iPhone."
        case .invalidURI(let uri):
            return "Can’t play \(uri)."
        case .soapFault(let fault):
            return fault
        case .commandFailed(let detail):
            return detail
        case .malformed(let detail):
            return detail
        case .network(let detail):
            return detail
        }
    }
}
