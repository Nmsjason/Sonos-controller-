import XCTest
@testable import SonosCore

final class CoreTests: XCTestCase {
    func testFixtureMatchesTheApprovedHomeCopy() throws {
        let snapshot = try FixtureLoader.loadSnapshot()
        XCTAssertEqual(snapshot.profile.initials, "JS")
        XCTAssertEqual(snapshot.household.summaryLine, "5 rooms playing · 1 group · 7 rooms")
        XCTAssertEqual(snapshot.household.roomCount, 7)
        XCTAssertEqual(snapshot.peers.map(\.name), ["Jason's iPhone", "Sarah's iPhone", "Guest iPhone"])
        let featured = try XCTUnwrap(snapshot.household.featuredGroup)
        XCTAssertEqual(featured.name, "Living Room + Kitchen")
        XCTAssertEqual(featured.playback.item?.title, "Glass Harbor")
        XCTAssertEqual(featured.playback.item?.artist, "The Velvet Satellites")
        XCTAssertEqual(featured.volume.value, 58)
        XCTAssertEqual(featured.playback.item?.art.shortLabel, "EMBER")
        XCTAssertEqual(featured.playback.item?.art.label, "EMBER TIDE")
        XCTAssertEqual(MediaTime.label(millis: 84_000), "1:24")
        XCTAssertEqual(MediaTime.remaining(positionMillis: 84_000, durationMillis: 222_000), "−2:18")
        XCTAssertEqual(snapshot.household.player(id: "RINCON_000E0000000101400")?.volume.value, 64)
        XCTAssertEqual(snapshot.household.player(id: "RINCON_000E0000000201400")?.volume.value, 46)
    }

    func testSummaryPluralizesASingleZone() {
        XCTAssertEqual(HouseholdSummary.line(playingZones: 1, multiRoomGroups: 1, rooms: 7), "1 room playing · 1 group · 7 rooms")
    }

    func testPauseAllAndVolumes() async throws {
        let controller = try makeController()
        try await controller.perform(.pauseAll)
        let paused = await controller.snapshot()
        XCTAssertEqual(paused.household.playingZoneCount, 0)
        XCTAssertEqual(paused.household.group(id: "RINCON_000E0000000701400")?.playback.state, .paused)
        try await controller.perform(.setGroupVolume(groupId: "RINCON_000E0000000101400", volume: 140))
        try await controller.perform(.setPlayerVolume(playerId: "RINCON_000E0000000301400", volume: -4))
        let volumes = await controller.snapshot()
        XCTAssertEqual(volumes.household.group(id: "RINCON_000E0000000101400")?.volume.value, 100)
        XCTAssertEqual(volumes.household.player(id: "RINCON_000E0000000301400")?.volume.value, 0)
    }

    func testPartyModeAndDownstairsPreset() async throws {
        let controller = try makeController()
        try await controller.perform(.activatePreset(id: "downstairs"))
        let downstairs = await controller.snapshot().household
        let group = try XCTUnwrap(downstairs.groups.first { $0.playerIds.count == 3 })
        XCTAssertEqual(group.playerIds, [
            "RINCON_000E0000000101400",
            "RINCON_000E0000000201400",
            "RINCON_000E0000000601400",
        ])
        XCTAssertEqual(group.name, "Living Room + 2")
        XCTAssertEqual(group.playback.item?.title, "Glass Harbor")
        XCTAssertEqual(downstairs.roomCount, 7)
        XCTAssertTrue(downstairs.groups.contains { $0.name == "Bedroom" })

        try await controller.perform(.partyMode)
        let party = await controller.snapshot().household
        XCTAssertEqual(party.groups.count, 1)
        XCTAssertEqual(party.groups[0].playerIds.count, 7)
        XCTAssertEqual(party.groups[0].coordinatorId, "RINCON_000E0000000101400")
        XCTAssertEqual(party.summaryLine, "1 room playing · 1 group · 7 rooms")
    }

    func testPlayOnReplacesTheGroupAndPandoraStaysOnFavorites() async throws {
        let snapshot = try FixtureLoader.loadSnapshot()
        let controller = MockSonosController(snapshot: snapshot)
        let lateNight = try XCTUnwrap(snapshot.catalog.flatMap(\.items).first { $0.title == "Late Night Drive" })
        try await controller.perform(.playItem(PlayRequest(
            playerIds: ["RINCON_000E0000000101400", "RINCON_000E0000000601400"],
            item: lateNight
        )))
        let playing = await controller.snapshot()
        let group = try XCTUnwrap(playing.household.group(id: "RINCON_000E0000000101400"))
        XCTAssertEqual(group.playerIds, ["RINCON_000E0000000101400", "RINCON_000E0000000601400"])
        XCTAssertEqual(group.playback.item?.title, "Late Night Drive")
        XCTAssertEqual(group.playback.state, .playing)

        let pandora = playing.sections(for: .pandora).flatMap(\.items)
        XCTAssertEqual(pandora.map(\.title), ["Focus Field Radio", "City After Dark", "Paper Lanterns"])
        XCTAssertTrue(pandora.allSatisfy { $0.favoriteId != nil })
        XCTAssertTrue(playing.sections(for: .spotify).contains { $0.title == "Jump Back In" })

        do {
            try await controller.perform(.loadPandoraFavorite(favoriteId: "not-a-station", groupId: group.id))
            XCTFail("Pandora playback must stay on saved favorites")
        } catch SonosError.pandoraLimitedToFavorites {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testSkipNextCyclesSpotifyCatalog() async throws {
        let controller = try makeController()
        try await controller.perform(.skipNext(groupId: "RINCON_000E0000000101400"))
        let title = await controller.snapshot().household.group(id: "RINCON_000E0000000101400")?.playback.item?.title
        XCTAssertEqual(title, "Golden Hour Mix")
    }

    func testControlFrameMatchesLocalWebSocketShape() throws {
        let message = ControlAPI.getGroups(householdId: "Sonos_abc")
        let decoded = try ControlMessage.decode(message.encoded())
        XCTAssertEqual(decoded.namespace, "groups")
        XCTAssertEqual(decoded.command, "getGroups")
        XCTAssertEqual(decoded.householdId, "Sonos_abc")
        XCTAssertEqual(decoded.header["sessionId"], .null)
        XCTAssertEqual(decoded.header["cmdId"], .null)
        XCTAssertEqual(decoded.body, .object([:]))

        let event = Data("""
        [{"namespace":"playback","type":"playbackStatus","groupId":"RINCON_000E0000000101400","householdId":"Sonos_jason_demo"},{"playbackState":"PLAYBACK_STATE_PAUSED","positionMillis":84000,"playModes":{"shuffle":true,"repeat":false,"repeatOne":false,"crossfade":false}}]
        """.utf8)
        let parsed = try ControlMessage.decode(event)
        XCTAssertTrue(parsed.isEvent)
        var household = try FixtureLoader.loadSnapshot().household
        household = HouseholdReducer.apply(parsed, to: household)
        let group = try XCTUnwrap(household.group(id: "RINCON_000E0000000101400"))
        XCTAssertEqual(group.playback.state, .paused)
        XCTAssertEqual(group.playback.positionMillis, 84_000)
        XCTAssertTrue(group.playback.playModes.shuffle)
        XCTAssertEqual(group.playback.item?.title, "Glass Harbor")
    }

    func testMetadataAndGroupEventsPreserveArt() throws {
        var household = try FixtureLoader.loadSnapshot().household
        let metadata = Data("""
        [{"namespace":"playbackMetadata","type":"metadataStatus","groupId":"RINCON_000E0000000101400"},{"currentItem":{"track":{"name":"Glass Harbor","artist":{"name":"The Velvet Satellites"},"album":{"name":"Ember Tide"},"durationMillis":222000}},"container":{"name":"Ember Tide","service":{"name":"Spotify"}}}]
        """.utf8)
        household = HouseholdReducer.apply(try ControlMessage.decode(metadata), to: household)
        XCTAssertEqual(household.group(id: "RINCON_000E0000000101400")?.playback.item?.art.label, "EMBER TIDE")

        let groups = Data("""
        [{"namespace":"groups","type":"groups","householdId":"Sonos_jason_demo"},{"groups":[{"id":"RINCON_000E0000000101400","name":"Living Room + Kitchen","coordinatorId":"RINCON_000E0000000101400","playbackState":"PLAYBACK_STATE_PLAYING","playerIds":["RINCON_000E0000000101400","RINCON_000E0000000201400","RINCON_000E0000000601400"]}]}]
        """.utf8)
        household = HouseholdReducer.apply(try ControlMessage.decode(groups), to: household)
        let group = try XCTUnwrap(household.group(id: "RINCON_000E0000000101400"))
        XCTAssertEqual(group.playerIds.count, 3)
        XCTAssertEqual(group.playback.item?.title, "Glass Harbor")
        XCTAssertEqual(group.volume.value, 58)

        let volume = Data("""
        [{"namespace":"groupVolume","type":"groupVolume","groupId":"RINCON_000E0000000101400"},{"volume":41,"muted":false}]
        """.utf8)
        household = HouseholdReducer.apply(try ControlMessage.decode(volume), to: household)
        XCTAssertEqual(household.group(id: "RINCON_000E0000000101400")?.volume.value, 41)
    }

    func testRouterKeepsCloudForTheWatchAndUPnPForSpotify() throws {
        let play = ControllerCommand.play(groupId: "g")
        XCTAssertEqual(try ControlRouter.route(play, context: .phoneOnLAN).get(), .localWebSocket)
        XCTAssertThrowsError(try ControlRouter.route(play, context: .phoneOffline).get())
        XCTAssertEqual(try ControlRouter.route(play, context: .watchOnPhone).get(), .phoneRelay)
        XCTAssertEqual(try ControlRouter.route(play, context: .watchAway).get(), .cloud)

        let spotify = ControllerCommand.loadSpotifyURI(uri: "spotify:track:abc", groupId: "g", title: nil)
        XCTAssertEqual(try ControlRouter.route(spotify, context: .phoneOnLAN).get(), .legacyUPnP)
        XCTAssertThrowsError(try ControlRouter.route(spotify, context: .phoneOffline).get())
        let queue = ControllerCommand.editQueue(groupId: "g", edit: .remove(track: 2))
        XCTAssertEqual(try ControlRouter.route(queue, context: .phoneOnLAN).get(), .legacyUPnP)
    }

    func testSpotifySOAPEscapesAndPandoraRejectsUnknownStations() throws {
        let household = try FixtureLoader.loadSnapshot().household
        let builder = LocalCommandBuilder()
        let calls = try builder.prepare(
            .loadSpotifyURI(uri: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6", groupId: "RINCON_000E0000000101400", title: "Glass & Harbor"),
            household: household,
            context: .phoneOnLAN
        )
        guard case let .upnp(action) = calls[0] else { return XCTFail("expected SOAP") }
        XCTAssertEqual(action.action, "SetAVTransportURI")
        XCTAssertEqual(action.url.absoluteString, "http://192.168.4.21:1400/MediaRenderer/AVTransport/Control")
        let soap = action.soapEnvelope()
        XCTAssertTrue(soap.contains("spotify%3atrack%3a6rqhFgbbKwnb9MLmUQDhG6"))
        XCTAssertTrue(soap.contains("sid=9"))
        XCTAssertTrue(soap.contains("&amp;flags=8224"))
        // The title is escaped inside the DIDL, then the DIDL is escaped into the SOAP argument.
        XCTAssertTrue(soap.contains("Glass &amp;amp; Harbor"))
        XCTAssertFalse(soap.contains("Glass & Harbor"))
        XCTAssertEqual(action.soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")

        XCTAssertThrowsError(try builder.prepare(
            .loadPandoraFavorite(favoriteId: "missing", groupId: "RINCON_000E0000000101400"),
            household: household,
            context: .phoneOnLAN
        ))

        let pandora = try builder.prepare(
            .loadPandoraFavorite(favoriteId: "fav-focus-field", groupId: "RINCON_000E0000000401400"),
            household: household,
            context: .phoneOnLAN
        )
        guard case let .upnp(station) = pandora[0] else { return XCTFail("expected pandora SOAP") }
        XCTAssertTrue(station.soapEnvelope().contains("x-sonosapi-radio:ST%3a4063"))
        XCTAssertEqual(station.url.host, "192.168.4.24")

        let play = try builder.prepare(.play(groupId: "RINCON_000E0000000101400"), household: household, context: .phoneOnLAN)
        guard case let .webSocket(message) = play[0] else { return XCTFail("play stays on the websocket") }
        XCTAssertEqual(message.command, "play")
        XCTAssertEqual(message.namespace, "playback")
    }

    func testQueueEditAndCloudAndWatchPaths() throws {
        let household = try FixtureLoader.loadSnapshot().household
        let builder = LocalCommandBuilder()
        let queue = try builder.prepare(
            .editQueue(groupId: "RINCON_000E0000000101400", edit: .insertNext(uri: "spotify:track:abc")),
            household: household,
            context: .phoneOnLAN
        )
        guard case let .upnp(action) = queue[0] else { return XCTFail("expected queue SOAP") }
        XCTAssertEqual(action.action, "AddURIToQueue")
        XCTAssertTrue(action.arguments.contains { $0.name == "EnqueueAsNext" && $0.value == "1" })

        let away = try builder.prepare(.pause(groupId: "RINCON_000E0000000101400"), household: household, context: .watchAway)
        guard case let .cloud(call) = away[0] else { return XCTFail("expected cloud") }
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.path, "/groups/RINCON_000E0000000101400/playback/pause")
        let base = URL(string: "https://api.ws.sonos.com/control/api/v1")!
        XCTAssertEqual(
            CloudEndpoint.url(base: base, path: call.path)?.absoluteString,
            "https://api.ws.sonos.com/control/api/v1/groups/RINCON_000E0000000101400/playback/pause"
        )

        let relay = try builder.prepare(.partyMode, household: household, context: .watchOnPhone)
        guard case let .phoneRelay(command) = relay[0] else { return XCTFail("expected phone relay") }
        let envelope = try WatchEnvelope.decode(try WatchEnvelope(command: command).encoded())
        XCTAssertEqual(envelope.command, .partyMode)
    }

    func testPlayItemGroupsOverWebSocketThenLoadsOverUPnP() throws {
        let snapshot = try FixtureLoader.loadSnapshot()
        let item = try XCTUnwrap(snapshot.catalog.flatMap(\.items).first { $0.id == "late-night" })
        let calls = try LocalCommandBuilder().prepare(
            .playItem(PlayRequest(playerIds: ["RINCON_000E0000000101400", "RINCON_000E0000000601400"], item: item)),
            household: snapshot.household,
            context: .phoneOnLAN
        )
        XCTAssertEqual(calls.count, 2)
        guard case let .webSocket(group) = calls[0], case let .upnp(load) = calls[1] else {
            return XCTFail("group then load")
        }
        XCTAssertEqual(group.command, "setGroupMembers")
        XCTAssertEqual(load.action, "SetAVTransportURI")
        XCTAssertTrue(load.soapEnvelope().contains("spotify%3aplaylist%3alatenightdrive"))
    }

    func testSSDPAndDeviceDescription() throws {
        let request = String(data: SSDPResponse.searchRequest(), encoding: .utf8)
        XCTAssertTrue(request?.contains("M-SEARCH * HTTP/1.1\r\n") == true)
        XCTAssertTrue(request?.contains("ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n") == true)
        let response = Data("""
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.4.21:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/81.0-00000 (ZPS13)\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USN: uuid:RINCON_000E0000000101400::urn:schemas-upnp-org:device:ZonePlayer:1\r
        X-RINCON-HOUSEHOLD: Sonos_jason_demo\r
        \r
        """.utf8)
        let parsed = try XCTUnwrap(SSDPResponse.parse(response))
        XCTAssertEqual(parsed.uuid, "RINCON_000E0000000101400")
        XCTAssertEqual(parsed.householdId, "Sonos_jason_demo")
        let speaker = try XCTUnwrap(DiscoveredSpeaker(ssdp: parsed))
        XCTAssertEqual(speaker.websocketURL.absoluteString, "wss://192.168.4.21:1443/websocket/api")
        XCTAssertEqual(speaker.source, .ssdp)

        let xml = """
        <root><device><friendlyName>Living Room</friendlyName><roomName>Living Room</roomName>\
        <UDN>uuid:RINCON_000E0000000101400</UDN><modelName>Sonos Port</modelName></device></root>
        """
        let description = try XCTUnwrap(DeviceDescription.parse(xml))
        XCTAssertEqual(description.roomName, "Living Room")
        XCTAssertEqual(description.udn, "RINCON_000E0000000101400")
        XCTAssertEqual(description.modelName, "Sonos Port")
    }

    func testMDNSQueryRoundTripAndCompressedPointer() throws {
        let query = try MDNSMessage.query(name: MDNSMessage.sonosService)
        let parsed = try MDNSMessage.parse(query)
        XCTAssertTrue(parsed.records.isEmpty)

        var writer = DNSWriter()
        writer.u16(0)
        writer.u16(0x8400)
        writer.u16(1)
        writer.u16(1)
        writer.u16(0)
        writer.u16(0)
        try writer.name("_sonos._tcp.local")
        writer.u16(MDNSMessage.ptrType)
        writer.u16(1)
        writer.u8(0xC0)
        writer.u8(12)
        writer.u16(MDNSMessage.ptrType)
        writer.u16(1)
        writer.u32(120)
        let rdata = try {
            var name = DNSWriter()
            try name.name("RINCON_000E0000000101400@Kitchen._sonos._tcp.local")
            return name.data
        }()
        writer.u16(UInt16(rdata.count))
        writer.bytes(rdata)
        let txt = MDNSMessage.encodeTXT([
            "uuid": "RINCON_000E0000000101400",
            "hhid": "Sonos_jason_demo",
            "n": "Jason's iPhone",
        ])
        XCTAssertEqual(MDNSMessage.decodeTXT(txt)["n"], "Jason's iPhone")
        XCTAssertEqual(MDNSMessage.decodeTXT(txt)["uuid"], "RINCON_000E0000000101400")

        let message = try MDNSMessage.parse(writer.data)
        XCTAssertEqual(message.records.first?.name, "_sonos._tcp.local")
        XCTAssertEqual(message.records.first?.ptr, "RINCON_000E0000000101400@Kitchen._sonos._tcp.local")
    }

    func testAssemblerPrefersBonjourAndFallsBackToSSDP() async throws {
        let location = "http://192.168.40.245:1400/xml/device_description.xml"
        let service = MDNSService(
            instance: "RINCON_74CA6026BB3201400@Kitchen._sonos._tcp.local",
            host: "Sonos-74CA6026BB32.local",
            port: 1443,
            addresses: [],
            txt: [
                "uuid": "RINCON_74CA6026BB3201400",
                "location": location,
                "hhid": "Sonos_CQqlcqStxh07fnkTNiSxC8yCha",
                "protovers": "1.51.2",
            ]
        )
        let speaker = try XCTUnwrap(DiscoveredSpeaker(mdns: service))
        XCTAssertEqual(speaker.id, "RINCON_74CA6026BB3201400")
        XCTAssertEqual(speaker.host, "192.168.40.245")
        XCTAssertEqual(speaker.householdId, "Sonos_CQqlcqStxh07fnkTNiSxC8yCha")
        XCTAssertEqual(speaker.websocketURL.absoluteString, "wss://192.168.40.245:1443/websocket/api")
        XCTAssertEqual(speaker.source, .bonjour)

        let bonjour = ScriptedBrowser(services: [service])
        let ssdp = ScriptedSSDP(responses: [])
        let discovery = SpeakerDiscovery(mdns: bonjour, ssdp: ssdp)
        let found = try await discovery.discover(timeout: 0.1)
        XCTAssertEqual(found.speakers.map(\.id), ["RINCON_74CA6026BB3201400"])
        XCTAssertFalse(found.usedSSDPFallback)
        XCTAssertEqual(ssdp.calls, 0)

        let response = SSDPResponse(
            location: URL(string: "http://10.0.0.8:1400/xml/device_description.xml")!,
            usn: "uuid:RINCON_000E0000000201400::urn:schemas-upnp-org:device:ZonePlayer:1",
            server: "Sonos",
            searchTarget: SSDPResponse.searchTarget,
            householdId: "Sonos_jason_demo",
            uuid: "RINCON_000E0000000201400"
        )
        let emptyBonjour = ScriptedBrowser(services: [])
        let fallback = ScriptedSSDP(responses: [response])
        let second = try await SpeakerDiscovery(mdns: emptyBonjour, ssdp: fallback).discover(timeout: 0.1)
        XCTAssertTrue(second.usedSSDPFallback)
        XCTAssertEqual(second.speakers.first?.source, .ssdp)
        XCTAssertEqual(fallback.calls, 1)
    }

    func testPresenceRoundTrip() {
        let advertisement = PresenceAdvertisement(
            peer: SessionPeer(id: "jason-iphone", name: "Jason's iPhone", groupId: "RINCON_000E0000000101400", presence: .active),
            householdId: "Sonos_jason_demo"
        )
        let parsed = PresenceAdvertisement.parse(txt: advertisement.txt())
        XCTAssertEqual(parsed, advertisement)
        XCTAssertEqual(MDNSMessage.decodeTXT(MDNSMessage.encodeTXT(advertisement.txt()))["n"], "Jason's iPhone")
    }

    func testSpotifySearchFixture() throws {
        let items = try SpotifyWebAPI.decodeSearch(FixtureLoader.spotifySearchData())
        XCTAssertEqual(items.map(\.title), ["Glass Harbor", "Late Night Drive", "The Velvet Satellites"])
        XCTAssertEqual(items[0].spotifyURI, "spotify:track:glassharbor")
        XCTAssertEqual(items[0].subtitle, "The Velvet Satellites · Ember Tide")
        let url = try XCTUnwrap(SpotifyWebAPI.searchURL(query: "glass harbor"))
        XCTAssertEqual(url.host, "api.spotify.com")
        XCTAssertTrue(url.query?.contains("type=track") == true || url.query?.contains("type=track,album,playlist,artist") == true)
    }

    func testWebSocketEndpoint() {
        XCTAssertEqual(ControlAPI.subprotocol, "v1.api.smartspeaker.audio")
        XCTAssertEqual(
            LocalWebSocketConfiguration.localDefault.apiKey,
            ControlAPI.localAPIKey
        )
        XCTAssertEqual(
            ControlAPI.websocketURL(host: "192.168.4.21").absoluteString,
            "wss://192.168.4.21:1443/websocket/api"
        )
    }

    func testLocalControllerSendsPlaybackOnTheWebSocket() async throws {
        let snapshot = try FixtureLoader.loadSnapshot()
        let socket = ScriptedSocket()
        let soap = ScriptedSOAP()
        let controller = LocalSonosController(
            snapshot: snapshot,
            context: .phoneOnLAN,
            realtime: socket,
            soap: soap
        )
        try await controller.perform(.pause(groupId: "RINCON_000E0000000101400"))
        let sent = await socket.sent()
        XCTAssertEqual(sent.map(\.command), ["pause"])
        let soaps = await soap.sent()
        XCTAssertTrue(soaps.isEmpty)

        try await controller.perform(.loadSpotifyURI(uri: "spotify:track:abc", groupId: "RINCON_000E0000000101400", title: "Glass Harbor"))
        let after = await soap.sent()
        XCTAssertEqual(after.map(\.action), ["SetAVTransportURI"])
    }

    func testUDPLoopback() throws {
        try UDPSocket.loopbackSelfTest()
    }

    private func makeController() throws -> MockSonosController {
        MockSonosController(snapshot: try FixtureLoader.loadSnapshot())
    }
}

private final class ScriptedBrowser: ServiceBrowser, @unchecked Sendable {
    var services: [MDNSService]
    init(services: [MDNSService]) { self.services = services }
    func browse(service: String, timeout: TimeInterval) async throws -> [MDNSService] { services }
}

private final class ScriptedSSDP: SSDPBrowsing, @unchecked Sendable {
    var responses: [SSDPResponse]
    var calls = 0
    init(responses: [SSDPResponse]) { self.responses = responses }
    func search(timeout: TimeInterval) async throws -> [SSDPResponse] {
        calls += 1
        return responses
    }
}

private final class ScriptedSocket: RealtimeSending, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [ControlMessage] = []
    func connect(url: URL) async throws {}
    func send(_ message: ControlMessage) async throws {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }
    func receive() async throws -> ControlMessage { throw SonosError.notConnected }
    func close() async {}
    func sent() async -> [ControlMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

private final class ScriptedSOAP: SOAPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [UPnPAction] = []
    func send(_ action: UPnPAction) async throws -> Data {
        lock.lock()
        actions.append(action)
        lock.unlock()
        return Data("ok".utf8)
    }
    func sent() async -> [UPnPAction] {
        lock.lock()
        defer { lock.unlock() }
        return actions
    }
}
