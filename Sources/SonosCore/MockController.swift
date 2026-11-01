import Foundation

public protocol SonosControlling: Sendable {
    func snapshot() async -> HouseholdSnapshot
    func updates() async -> AsyncStream<HouseholdSnapshot>
    func perform(_ command: ControllerCommand) async throws
}

public final class MockSonosController: SonosControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var state: HouseholdSnapshot
    private var continuations: [UUID: AsyncStream<HouseholdSnapshot>.Continuation] = [:]
    private var edits: [QueueEdit] = []

    public init(snapshot: HouseholdSnapshot) {
        self.state = snapshot
    }

    public func snapshot() async -> HouseholdSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func queueEdits() async -> [QueueEdit] {
        lock.lock()
        defer { lock.unlock() }
        return edits
    }

    public func updates() async -> AsyncStream<HouseholdSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let current = state
            lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    public func perform(_ command: ControllerCommand) async throws {
        try mutate { snapshot in
            switch command {
            case let .play(groupId):
                snapshot.household = snapshot.household.updatingGroup(groupId) { group in
                    if group.playback.item != nil {
                        group.playback.state = .playing
                    }
                }
            case let .pause(groupId):
                snapshot.household = snapshot.household.updatingGroup(groupId) { group in
                    if group.playback.state == .playing {
                        group.playback.state = .paused
                    }
                }
            case .pauseAll:
                for index in snapshot.household.groups.indices where snapshot.household.groups[index].playback.state == .playing {
                    snapshot.household.groups[index].playback.state = .paused
                }
            case let .skipNext(groupId):
                try step(snapshot: &snapshot, groupId: groupId, direction: 1)
            case let .skipPrevious(groupId):
                try step(snapshot: &snapshot, groupId: groupId, direction: -1)
            case let .seek(groupId, position):
                snapshot.household = snapshot.household.updatingGroup(groupId) { group in
                    let duration = max(group.playback.durationMillis, 0)
                    group.playback.positionMillis = min(max(0, position), duration == 0 ? position : duration)
                }
            case let .setPlayModes(groupId, modes):
                snapshot.household = snapshot.household.updatingGroup(groupId) { $0.playback.playModes = modes }
            case let .setGroupVolume(groupId, volume):
                snapshot.household = snapshot.household.updatingGroup(groupId) {
                    $0.volume = Volume(value: volume, muted: $0.volume.muted)
                }
            case let .setPlayerVolume(playerId, volume):
                snapshot.household = snapshot.household.updatingPlayer(playerId) {
                    $0.volume = Volume(value: volume, muted: $0.volume.muted)
                }
            case let .setGroupMembers(_, playerIds), let .createGroup(playerIds):
                snapshot.household = snapshot.household.regrouping(playerIds)
            case .partyMode:
                let ordered = snapshot.household.players.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
                let coordinator = snapshot.household.featuredGroup?.coordinatorId
                snapshot.household = snapshot.household.regrouping(promote(coordinator, in: ordered))
            case let .activatePreset(id):
                guard let preset = snapshot.household.preset(id: id) else {
                    throw SonosError.commandFailed("Unknown preset \(id)")
                }
                snapshot.household = snapshot.household.regrouping(preset.playerIds)
            case let .loadFavorite(favoriteId, groupId):
                guard let favorite = snapshot.household.favorite(id: favoriteId) else {
                    throw SonosError.commandFailed("Unknown favorite \(favoriteId)")
                }
                try load(favorite: favorite, groupId: groupId, snapshot: &snapshot)
            case let .loadSpotifyURI(uri, groupId, title):
                try loadSpotify(uri: uri, title: title, groupId: groupId, snapshot: &snapshot)
            case let .loadPandoraFavorite(favoriteId, groupId):
                guard let favorite = snapshot.household.favorite(id: favoriteId), favorite.source == .pandora else {
                    throw SonosError.pandoraLimitedToFavorites
                }
                try load(favorite: favorite, groupId: groupId, snapshot: &snapshot)
            case let .editQueue(_, edit):
                edits.append(edit)
            case let .playItem(request):
                snapshot.household = snapshot.household.regrouping(request.playerIds)
                let groupId = request.playerIds.first ?? ""
                if request.item.source == .pandora {
                    guard let favoriteId = request.item.favoriteId,
                          let favorite = snapshot.household.favorite(id: favoriteId) else {
                        throw SonosError.pandoraLimitedToFavorites
                    }
                    try load(favorite: favorite, groupId: groupId, snapshot: &snapshot)
                } else {
                    try loadCatalog(request.item, groupId: groupId, snapshot: &snapshot)
                }
            }
        }
    }

    private func mutate(_ body: (inout HouseholdSnapshot) throws -> Void) throws {
        lock.lock()
        var copy = state
        do {
            try body(&copy)
        } catch {
            lock.unlock()
            throw error
        }
        state = copy
        let continuations = Array(self.continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(copy) }
    }

    private func load(favorite: Favorite, groupId: String, snapshot: inout HouseholdSnapshot) throws {
        let item = NowPlayingItem(
            title: favorite.name,
            artist: favorite.subtitle,
            album: favorite.name,
            source: favorite.source,
            art: favorite.art,
            spotifyURI: favorite.spotifyURI
        )
        snapshot.household = snapshot.household.updatingGroup(groupId) { group in
            group.playback.state = .playing
            group.playback.positionMillis = 0
            group.playback.durationMillis = favorite.kind == .station ? 0 : 180_000
            group.playback.item = item
        }
    }

    private func loadSpotify(uri: String, title: String?, groupId: String, snapshot: inout HouseholdSnapshot) throws {
        guard uri.hasPrefix("spotify:") else { throw SonosError.invalidURI(uri) }
        let item = NowPlayingItem(
            title: title ?? uri,
            artist: "Spotify",
            album: "",
            source: .spotify,
            art: .placeholder(for: .spotify),
            spotifyURI: uri
        )
        snapshot.household = snapshot.household.updatingGroup(groupId) { group in
            group.playback.state = .playing
            group.playback.positionMillis = 0
            group.playback.item = item
        }
    }

    private func loadCatalog(_ item: CatalogItem, groupId: String, snapshot: inout HouseholdSnapshot) throws {
        let now = NowPlayingItem(
            title: item.title,
            artist: item.subtitle,
            album: item.title,
            source: item.source,
            art: item.art,
            spotifyURI: item.spotifyURI
        )
        snapshot.household = snapshot.household.updatingGroup(groupId) { group in
            group.playback.state = .playing
            group.playback.positionMillis = 0
            group.playback.durationMillis = 180_000
            group.playback.item = now
        }
    }

    private func step(snapshot: inout HouseholdSnapshot, groupId: String, direction: Int) throws {
        guard let group = snapshot.household.group(id: groupId) else { return }
        let source = group.playback.item?.source ?? .spotify
        let pool = snapshot.catalog
            .filter { $0.source == source }
            .flatMap(\.items)
        guard !pool.isEmpty else { return }
        let current = pool.firstIndex { $0.title == group.playback.item?.title } ?? (direction > 0 ? -1 : 0)
        let nextIndex = (current + direction + pool.count) % pool.count
        try loadCatalog(pool[nextIndex], groupId: groupId, snapshot: &snapshot)
    }

    private func promote(_ id: String?, in ids: [String]) -> [String] {
        guard let id, let index = ids.firstIndex(of: id) else { return ids }
        var copy = ids
        copy.insert(copy.remove(at: index), at: 0)
        return copy
    }
}
