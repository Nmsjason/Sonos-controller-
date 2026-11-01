import Foundation

public enum HouseholdReducer {
    public static func apply(_ message: ControlMessage, to household: Household) -> Household {
        guard let namespace = message.namespace else { return household }
        let fields = message.fields
        switch namespace {
        case "playback":
            return applyPlayback(fields, to: household)
        case "playbackMetadata":
            return applyMetadata(fields, to: household)
        case "groupVolume":
            return applyGroupVolume(fields, to: household)
        case "playerVolume":
            return applyPlayerVolume(fields, to: household)
        case "groups":
            return applyGroups(fields, to: household)
        default:
            return household
        }
    }

    private static func applyPlayback(_ fields: [String: JSONValue], to household: Household) -> Household {
        guard let groupId = fields["groupId"]?.string else { return household }
        return household.updatingGroup(groupId) { group in
            if let raw = fields["playbackState"]?.string, let state = PlaybackState.fromSonos(raw) {
                group.playback.state = state
            }
            if let position = fields["positionMillis"]?.int {
                group.playback.positionMillis = max(0, position)
            }
            if let modes = fields["playModes"]?.object {
                if let shuffle = modes["shuffle"]?.bool { group.playback.playModes.shuffle = shuffle }
                if let repeatAll = modes["repeat"]?.bool { group.playback.playModes.repeat = repeatAll }
                if let repeatOne = modes["repeatOne"]?.bool { group.playback.playModes.repeatOne = repeatOne }
                if let crossfade = modes["crossfade"]?.bool { group.playback.playModes.crossfade = crossfade }
            }
        }
    }

    private static func applyMetadata(_ fields: [String: JSONValue], to household: Household) -> Household {
        guard let groupId = fields["groupId"]?.string else { return household }
        let track = fields["currentItem"]?["track"]
        let title = track?["name"]?.string
        guard let title else { return household }
        let artist = name(track?["artist"]) ?? ""
        let album = name(track?["album"]) ?? (fields["container"]?["name"]?.string ?? "")
        let service = name(fields["container"]?["service"]) ?? name(track?["service"])
        let source = source(from: service)
        let duration = track?["durationMillis"]?.int
        return household.updatingGroup(groupId) { group in
            let art: ArtPalette
            if group.playback.item?.title == title, let existing = group.playback.item?.art {
                art = existing
            } else {
                art = .placeholder(for: source ?? group.playback.item?.source ?? .other)
            }
            group.playback.item = NowPlayingItem(
                title: title,
                artist: artist,
                album: album,
                source: source ?? group.playback.item?.source ?? .other,
                art: art,
                spotifyURI: group.playback.item?.spotifyURI
            )
            if let duration {
                group.playback.durationMillis = duration
            }
        }
    }

    private static func applyGroupVolume(_ fields: [String: JSONValue], to household: Household) -> Household {
        guard let groupId = fields["groupId"]?.string, let volume = fields["volume"]?.int else { return household }
        return household.updatingGroup(groupId) { group in
            group.volume = Volume(value: volume, muted: fields["muted"]?.bool ?? group.volume.muted)
        }
    }

    private static func applyPlayerVolume(_ fields: [String: JSONValue], to household: Household) -> Household {
        guard let playerId = fields["playerId"]?.string, let volume = fields["volume"]?.int else { return household }
        return household.updatingPlayer(playerId) { player in
            player.volume = Volume(value: volume, muted: fields["muted"]?.bool ?? player.volume.muted)
        }
    }

    private static func applyGroups(_ fields: [String: JSONValue], to household: Household) -> Household {
        guard let rawGroups = fields["groups"]?.array else { return household }
        var household = household
        var next: [PlayerGroup] = []
        for raw in rawGroups {
            guard let object = raw.object, let id = object["id"]?.string else { continue }
            let playerIds = object["playerIds"]?.array?.compactMap(\.string) ?? []
            let coordinator = object["coordinatorId"]?.string ?? playerIds.first ?? id
            let existing = household.group(id: id) ?? household.group(id: coordinator)
            var playback = existing?.playback ?? .idle
            if let rawState = object["playbackState"]?.string, let state = PlaybackState.fromSonos(rawState) {
                playback.state = state
            }
            let name = object["name"]?.string ?? household.makeGroupName(coordinatorId: coordinator, playerIds: playerIds)
            next.append(
                PlayerGroup(
                    id: id,
                    name: name,
                    coordinatorId: coordinator,
                    playerIds: playerIds.isEmpty ? [coordinator] : playerIds,
                    volume: existing?.volume ?? Volume(value: 20),
                    playback: playback
                )
            )
        }
        if !next.isEmpty {
            household.groups = next
        }
        return household
    }

    private static func name(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = value.string { return string }
        return value["name"]?.string
    }

    private static func source(from service: String?) -> MusicSource? {
        guard let service else { return nil }
        let folded = service.lowercased()
        if folded.contains("spotify") { return .spotify }
        if folded.contains("pandora") { return .pandora }
        return .other
    }
}
