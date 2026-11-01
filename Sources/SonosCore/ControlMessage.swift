import Foundation

/// One Control API frame. On the wire this is a JSON array `[header, body]`, the same shape the
/// cloud Control API uses and that speakers accept on `wss://<ip>:1443/websocket/api`.
public struct ControlMessage: Equatable, Sendable {
    public var header: [String: JSONValue]
    public var body: JSONValue

    public init(header: [String: JSONValue], body: JSONValue = .object([:])) {
        self.header = header
        self.body = body
    }

    public var namespace: String? { header["namespace"]?.string }
    public var command: String? { header["command"]?.string }
    public var response: String? { header["response"]?.string }
    public var eventType: String? { header["type"]?.string }
    public var groupId: String? { header["groupId"]?.string }
    public var playerId: String? { header["playerId"]?.string }
    public var householdId: String? { header["householdId"]?.string }
    public var succeeded: Bool? { header["success"]?.bool }

    /// Events carry a `type` and no command response. Replies carry `success` or `response`.
    public var isEvent: Bool {
        eventType != nil && response == nil && succeeded == nil
    }

    public static func command(
        namespace: String,
        command: String,
        householdId: String? = nil,
        groupId: String? = nil,
        playerId: String? = nil,
        body: [String: JSONValue] = [:]
    ) -> ControlMessage {
        var header: [String: JSONValue] = [
            "namespace": .string(namespace),
            "command": .string(command),
            "sessionId": .null,
            "cmdId": .null,
        ]
        if let householdId { header["householdId"] = .string(householdId) }
        if let groupId { header["groupId"] = .string(groupId) }
        if let playerId { header["playerId"] = .string(playerId) }
        return ControlMessage(header: header, body: .object(body))
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode([JSONValue.object(header), body])
    }

    public static func decode(_ data: Data) throws -> ControlMessage {
        let values = try JSONDecoder().decode([JSONValue].self, from: data)
        if values.count >= 2, let header = values[0].object {
            return ControlMessage(header: header, body: values[1])
        }
        if values.count == 1, let header = values[0].object {
            return ControlMessage(header: header, body: .object([:]))
        }
        throw SonosError.malformed("Control API frame was not a [header, body] array")
    }

    /// Header overlaid with the body object, so reducers can read fields from either place.
    public var fields: [String: JSONValue] {
        var merged = header
        if let object = body.object {
            for (key, value) in object {
                merged[key] = value
            }
        }
        return merged
    }
}

public enum ControlAPI {
    public static let websocketPath = "/websocket/api"
    public static let websocketPort = 1443
    public static let subprotocol = "v1.api.smartspeaker.audio"
    /// Local firmware accepts a client-supplied key. This is not a cloud credential.
    public static let localAPIKey = "12345678-abcd-1234-5678-123456789000"

    public static func websocketURL(host: String, port: Int = websocketPort) -> URL {
        URL(string: "wss://\(host):\(port)\(websocketPath)")!
    }

    public static func getGroups(householdId: String) -> ControlMessage {
        .command(namespace: "groups", command: "getGroups", householdId: householdId)
    }

    public static func subscribe(namespace: String, householdId: String, groupId: String? = nil, playerId: String? = nil) -> ControlMessage {
        .command(namespace: namespace, command: "subscribe", householdId: householdId, groupId: groupId, playerId: playerId)
    }

    public static func play(groupId: String, householdId: String) -> ControlMessage {
        .command(namespace: "playback", command: "play", householdId: householdId, groupId: groupId)
    }

    public static func pause(groupId: String, householdId: String) -> ControlMessage {
        .command(namespace: "playback", command: "pause", householdId: householdId, groupId: groupId)
    }

    public static func skipToNextTrack(groupId: String, householdId: String) -> ControlMessage {
        .command(namespace: "playback", command: "skipToNextTrack", householdId: householdId, groupId: groupId)
    }

    public static func skipToPreviousTrack(groupId: String, householdId: String) -> ControlMessage {
        .command(namespace: "playback", command: "skipToPreviousTrack", householdId: householdId, groupId: groupId)
    }

    public static func seek(groupId: String, householdId: String, positionMillis: Int) -> ControlMessage {
        .command(
            namespace: "playback",
            command: "seek",
            householdId: householdId,
            groupId: groupId,
            body: ["positionMillis": .int(positionMillis)]
        )
    }

    public static func setPlayModes(groupId: String, householdId: String, modes: PlayModes) -> ControlMessage {
        .command(
            namespace: "playback",
            command: "setPlayModes",
            householdId: householdId,
            groupId: groupId,
            body: [
                "playModes": .object([
                    "shuffle": .bool(modes.shuffle),
                    "repeat": .bool(modes.repeat),
                    "repeatOne": .bool(modes.repeatOne),
                    "crossfade": .bool(modes.crossfade),
                ]),
            ]
        )
    }

    public static func setGroupVolume(groupId: String, householdId: String, volume: Int) -> ControlMessage {
        .command(
            namespace: "groupVolume",
            command: "setVolume",
            householdId: householdId,
            groupId: groupId,
            body: ["volume": .int(volume)]
        )
    }

    public static func setPlayerVolume(playerId: String, householdId: String, volume: Int) -> ControlMessage {
        .command(
            namespace: "playerVolume",
            command: "setVolume",
            householdId: householdId,
            playerId: playerId,
            body: ["volume": .int(volume)]
        )
    }

    public static func createGroup(householdId: String, playerIds: [String]) -> ControlMessage {
        .command(
            namespace: "groups",
            command: "createGroup",
            householdId: householdId,
            body: ["playerIds": .array(playerIds.map(JSONValue.string))]
        )
    }

    public static func setGroupMembers(groupId: String, householdId: String, playerIds: [String]) -> ControlMessage {
        .command(
            namespace: "groups",
            command: "setGroupMembers",
            householdId: householdId,
            groupId: groupId,
            body: ["playerIds": .array(playerIds.map(JSONValue.string))]
        )
    }

    public static func getFavorites(householdId: String) -> ControlMessage {
        .command(namespace: "favorites", command: "getFavorites", householdId: householdId)
    }
}
