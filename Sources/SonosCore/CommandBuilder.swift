import Foundation

public enum AVTransport {
    public static let serviceURN = "urn:schemas-upnp-org:service:AVTransport:1"

    public static func controlURL(host: String) -> URL {
        URL(string: "http://\(host):1400/MediaRenderer/AVTransport/Control")!
    }
}

public struct LocalCommandBuilder: Sendable {
    public var account: SonosMusicServiceAccount

    public init(account: SonosMusicServiceAccount = SonosMusicServiceAccount()) {
        self.account = account
    }

    public func prepare(
        _ command: ControllerCommand,
        household: Household,
        context: ControlContext
    ) throws -> [PreparedCall] {
        let path = try ControlRouter.route(command, context: context).get()
        switch path {
        case .phoneRelay:
            return [.phoneRelay(command)]
        case .cloud:
            return try [cloudCall(command, household: household)].map(PreparedCall.cloud)
        case .localWebSocket:
            return try websocketCalls(command, household: household).map(PreparedCall.webSocket)
        case .legacyUPnP:
            return try legacyCalls(command, household: household)
        }
    }

    private func websocketCalls(_ command: ControllerCommand, household: Household) throws -> [ControlMessage] {
        let home = household.id
        switch command {
        case let .play(groupId):
            return [ControlAPI.play(groupId: groupId, householdId: home)]
        case let .pause(groupId):
            return [ControlAPI.pause(groupId: groupId, householdId: home)]
        case .pauseAll:
            return household.groups
                .filter { $0.playback.state == .playing }
                .map { ControlAPI.pause(groupId: $0.id, householdId: home) }
        case let .skipNext(groupId):
            return [ControlAPI.skipToNextTrack(groupId: groupId, householdId: home)]
        case let .skipPrevious(groupId):
            return [ControlAPI.skipToPreviousTrack(groupId: groupId, householdId: home)]
        case let .seek(groupId, position):
            return [ControlAPI.seek(groupId: groupId, householdId: home, positionMillis: position)]
        case let .setPlayModes(groupId, modes):
            return [ControlAPI.setPlayModes(groupId: groupId, householdId: home, modes: modes)]
        case let .setGroupVolume(groupId, volume):
            return [ControlAPI.setGroupVolume(groupId: groupId, householdId: home, volume: clamp(volume))]
        case let .setPlayerVolume(playerId, volume):
            return [ControlAPI.setPlayerVolume(playerId: playerId, householdId: home, volume: clamp(volume))]
        case let .setGroupMembers(_, playerIds), let .createGroup(playerIds):
            return [groupMessage(playerIds: playerIds, household: household)]
        case .partyMode:
            let ordered = household.players.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
            let coordinator = household.featuredGroup?.coordinatorId
            let ids = promote(coordinator, in: ordered)
            return [groupMessage(playerIds: ids, household: household)]
        case let .activatePreset(id):
            guard let preset = household.preset(id: id) else {
                throw SonosError.commandFailed("Unknown preset \(id)")
            }
            return [groupMessage(playerIds: preset.playerIds, household: household)]
        case .loadFavorite, .loadSpotifyURI, .loadPandoraFavorite, .editQueue, .playItem:
            throw SonosError.commandFailed("\(command) is a legacy UPnP command")
        }
    }

    private func legacyCalls(_ command: ControllerCommand, household: Household) throws -> [PreparedCall] {
        switch command {
        case let .loadSpotifyURI(uri, groupId, title):
            return [try .upnp(setSpotify(uri: uri, title: title ?? uri, groupId: groupId, household: household))]
        case let .loadPandoraFavorite(favoriteId, groupId):
            return [try .upnp(setPandora(favoriteId: favoriteId, groupId: groupId, household: household))]
        case let .loadFavorite(favoriteId, groupId):
            guard let favorite = household.favorite(id: favoriteId) else {
                throw SonosError.commandFailed("Unknown favorite \(favoriteId)")
            }
            if favorite.source == .pandora {
                return [try .upnp(setPandora(favoriteId: favoriteId, groupId: groupId, household: household))]
            }
            if let spotify = favorite.spotifyURI {
                return [try .upnp(setSpotify(uri: spotify, title: favorite.name, groupId: groupId, household: household))]
            }
            throw SonosError.commandFailed("Favorite \(favoriteId) has no playable URI")
        case let .editQueue(groupId, edit):
            return [try .upnp(queueAction(edit, groupId: groupId, household: household))]
        case let .playItem(request):
            let groupCall = PreparedCall.webSocket(groupMessage(playerIds: request.playerIds, household: household))
            let groupId = request.playerIds.first ?? ""
            switch request.item.source {
            case .spotify:
                guard let uri = request.item.spotifyURI else {
                    throw SonosError.invalidURI(request.item.title)
                }
                let soap = try setSpotify(uri: uri, title: request.item.title, groupId: groupId, household: household)
                return [groupCall, .upnp(soap)]
            case .pandora:
                guard let favoriteId = request.item.favoriteId else {
                    throw SonosError.pandoraLimitedToFavorites
                }
                let soap = try setPandora(favoriteId: favoriteId, groupId: groupId, household: household)
                return [groupCall, .upnp(soap)]
            case .other:
                throw SonosError.commandFailed("No legacy loader for this source")
            }
        default:
            throw SonosError.commandFailed("Not a legacy command")
        }
    }

    private func cloudCall(_ command: ControllerCommand, household: Household) throws -> CloudCall {
        let home = household.id
        switch command {
        case .pauseAll:
            return CloudCall(method: "POST", path: "/households/\(home)/playback/pause", body: nil)
        case let .play(groupId):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/playback/play")
        case let .pause(groupId):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/playback/pause")
        case let .skipNext(groupId):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/playback/skipToNextTrack")
        case let .skipPrevious(groupId):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/playback/skipToPreviousTrack")
        case let .seek(groupId, position):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/playback/seek", body: .object(["positionMillis": .int(position)]))
        case let .setGroupVolume(groupId, volume):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/groupVolume", body: .object(["volume": .int(clamp(volume))]))
        case let .setPlayerVolume(playerId, volume):
            return CloudCall(method: "POST", path: "/players/\(playerId)/playerVolume", body: .object(["volume": .int(clamp(volume))]))
        case .partyMode, .createGroup, .setGroupMembers, .activatePreset:
            return CloudCall(method: "POST", path: "/households/\(home)/groups/createGroup")
        case let .playItem(request):
            let groupId = request.playerIds.first ?? household.featuredGroup?.id ?? ""
            return CloudCall(
                method: "POST",
                path: "/groups/\(groupId)/playbackSession/loadCloudQueue",
                body: .object(["itemId": .string(request.item.spotifyURI ?? request.item.favoriteId ?? request.item.id)])
            )
        case let .loadSpotifyURI(uri, groupId, _):
            return CloudCall(
                method: "POST",
                path: "/groups/\(groupId)/playbackSession/loadCloudQueue",
                body: .object(["spotifyURI": .string(uri)])
            )
        case let .loadPandoraFavorite(favoriteId, groupId), let .loadFavorite(favoriteId, groupId):
            return CloudCall(
                method: "POST",
                path: "/groups/\(groupId)/favorites",
                body: .object(["favoriteId": .string(favoriteId), "playOnCompletion": .bool(true)])
            )
        case let .editQueue(groupId, _):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/playbackSession/skipToItem")
        case let .setPlayModes(groupId, _):
            return CloudCall(method: "POST", path: "/groups/\(groupId)/playback/playMode")
        }
    }

    private func groupMessage(playerIds: [String], household: Household) -> ControlMessage {
        let ids = uniquePreservingOrder(playerIds)
        if let existing = household.groups.first(where: { $0.coordinatorId == ids.first }) {
            return ControlAPI.setGroupMembers(groupId: existing.id, householdId: household.id, playerIds: ids)
        }
        return ControlAPI.createGroup(householdId: household.id, playerIds: ids)
    }

    private func setSpotify(uri: String, title: String, groupId: String, household: Household) throws -> UPnPAction {
        let host = try coordinatorHost(groupId: groupId, household: household)
        let sonosURI = try SpotifySonosURI.sonosURI(from: uri, account: account)
        let didl = didl(title: title, uri: sonosURI, itemClass: SpotifySonosURI.didlClass(for: uri))
        return UPnPAction(
            url: AVTransport.controlURL(host: host),
            serviceURN: AVTransport.serviceURN,
            action: "SetAVTransportURI",
            arguments: [
                ("InstanceID", "0"),
                ("CurrentURI", sonosURI),
                ("CurrentURIMetaData", didl),
            ]
        )
    }

    private func setPandora(favoriteId: String, groupId: String, household: Household) throws -> UPnPAction {
        guard let favorite = household.favorite(id: favoriteId), favorite.source == .pandora, let uri = favorite.sonosURI else {
            throw SonosError.pandoraLimitedToFavorites
        }
        let host = try coordinatorHost(groupId: groupId, household: household)
        let didl = didl(title: favorite.name, uri: uri, itemClass: "object.item.audioItem.audioBroadcast")
        return UPnPAction(
            url: AVTransport.controlURL(host: host),
            serviceURN: AVTransport.serviceURN,
            action: "SetAVTransportURI",
            arguments: [
                ("InstanceID", "0"),
                ("CurrentURI", uri),
                ("CurrentURIMetaData", didl),
            ]
        )
    }

    private func queueAction(_ edit: QueueEdit, groupId: String, household: Household) throws -> UPnPAction {
        let host = try coordinatorHost(groupId: groupId, household: household)
        let url = AVTransport.controlURL(host: host)
        switch edit {
        case let .append(uri), let .insertNext(uri):
            let enqueued = uri.hasPrefix("spotify:") ? (try SpotifySonosURI.sonosURI(from: uri, account: account)) : uri
            let asNext = if case .insertNext = edit { "1" } else { "0" }
            return UPnPAction(
                url: url,
                serviceURN: AVTransport.serviceURN,
                action: "AddURIToQueue",
                arguments: [
                    ("InstanceID", "0"),
                    ("EnqueuedURI", enqueued),
                    ("EnqueuedURIMetaData", ""),
                    ("DesiredFirstTrackNumberEnqueued", "0"),
                    ("EnqueueAsNext", asNext),
                ]
            )
        case let .remove(track):
            return UPnPAction(
                url: url,
                serviceURN: AVTransport.serviceURN,
                action: "RemoveTrackFromQueue",
                arguments: [
                    ("InstanceID", "0"),
                    ("ObjectID", "Q:0/\(track)"),
                    ("UpdateID", "0"),
                ]
            )
        case let .reorder(from, to):
            return UPnPAction(
                url: url,
                serviceURN: AVTransport.serviceURN,
                action: "ReorderTracksInQueue",
                arguments: [
                    ("InstanceID", "0"),
                    ("StartingIndex", "\(from)"),
                    ("NumberOfTracks", "1"),
                    ("InsertBefore", "\(to)"),
                    ("UpdateID", "0"),
                ]
            )
        }
    }

    private func coordinatorHost(groupId: String, household: Household) throws -> String {
        let group = household.group(id: groupId) ?? household.groups.first { $0.playerIds.contains(groupId) }
        let coordinator = group?.coordinatorId ?? groupId
        guard let host = household.player(id: coordinator)?.host, !host.isEmpty else {
            throw SonosError.speakerUnreachable
        }
        return host
    }

    private func didl(title: String, uri: String, itemClass: String) -> String {
        """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="00032020" parentID="-1" restricted="true">\
        <dc:title>\(XML.escape(title))</dc:title>\
        <upnp:class>\(itemClass)</upnp:class>\
        <res protocolInfo="sonos.com-http:*:*:*">\(XML.escape(uri))</res>\
        </item></DIDL-Lite>
        """
    }

    private func promote(_ id: String?, in ids: [String]) -> [String] {
        guard let id, let index = ids.firstIndex(of: id) else { return ids }
        var copy = ids
        let value = copy.remove(at: index)
        copy.insert(value, at: 0)
        return copy
    }

    private func clamp(_ volume: Int) -> Int { min(100, max(0, volume)) }
}
