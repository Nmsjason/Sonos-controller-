# Sonos Controller

Jason's controller for the house. Espresso, smoked walnut, and brushed brass, with album art tinting the rooms. The approved screens are the source of truth: Home, Now Playing, Group Rooms, Browse with the Play On sheet, and the Apple Watch now-playing face.

The iPhone and the Watch share one Swift package, `SonosCore`. A Windows client can come later as a C# / Avalonia port of that core. The household fixture in `Sources/SonosCore/Resources/jason-household.json` is the shared sample both sides can load.

## Architecture

```
iPhone app                         Watch app
    │                                  │
    │  SonosSession (mock today)       │  same models, crown volume
    ▼                                  │
SonosCore                              │  WatchConnectivity
    │                                  ▼
    ├─ SpeakerDiscovery                phone relay, or cloud if the phone is out of range
    │    Bonjour _sonos._tcp
    │    SSDP only if Bonjour is empty
    ├─ LocalWebSocketClient   wss://<speaker>:1443/websocket/api
    ├─ UPnP / SOAP            http://<speaker>:1400   queue, Spotify URIs, Pandora favorites
    └─ Cloud Control API      only when the Watch is away from the iPhone
```

Speakers are controlled on the LAN first. The socket on port **1443** speaks the same JSON as the official Sonos Control API: a frame is `[header, body]`, with `namespace`, `command`, and the household, group, or player id. The subprotocol is `v1.api.smartspeaker.audio`. Local firmware accepts a client API key; it is not a cloud OAuth token. The default is documented on `ControlAPI.localAPIKey`.

**UPnP on port 1400 is legacy and stays behind one adapter.** `LocalCommandBuilder` sends play, pause, volume, and grouping over the WebSocket. It drops to SOAP only for queue edits (`AddURIToQueue`, `RemoveTrackFromQueue`, `ReorderTracksInQueue`) and for loading a Spotify URI or a Pandora station (`SetAVTransportURI`). Spotify URIs are rewritten to `x-sonos-spotify:…`. The service id and account serial differ per household and are parameters, not constants baked into the UI.

**The cloud Control API is not a general fallback.** `ControlRouter` sends the Watch through the iPhone when `WCSession` is reachable. The phone then uses the LAN. If the Watch is away from the phone, the same command is mapped onto `https://api.ws.sonos.com/control/api/v1`. A phone that cannot see speakers reports not connected. It does not silently switch to the cloud.

### Discovery

1. Browse `_sonos._tcp` (Bonjour). On iOS this is `NWBrowser`, which does not need the multicast entitlement. On Linux the package sends an mDNS query with the QU bit so the speaker can unicast the answer. TXT records used here match what speakers advertise: `uuid`, `location`, `hhid`, `protovers`.
2. If that returns nothing, SSDP `M-SEARCH` for `urn:schemas-upnp-org:device:ZonePlayer:1` to `239.255.255.250:1900`. The `LOCATION` header is `http://<ip>:1400/xml/device_description.xml`.

### Users joined to session

Several iPhones can be in the same group at once. Each phone should advertise `_jasonssonos._tcp` while it is controlling a group. The TXT record is small and stable:

| Key | Meaning |
| --- | --- |
| `v` | `1` |
| `id` | stable peer id |
| `n` | "Jason's iPhone" |
| `h` | household id |
| `g` | group id being controlled |
| `p` | `active` or `guest` |

Other phones browse the same service and filter on household and group. Bonjour is a better fit than Multipeer Connectivity because a future Windows client can see the same records, and because it does not ask people to pair. `MockSessionPresence` returns the three phones from the fixture until a real browse is wired into the session. `BonjourSessionPresence` is the Apple implementation of that browse.

### Spotify and Pandora

Spotify search and browse go to the Spotify Web API (`SpotifyWebAPI`). Sonos still does the playing, via the UPnP URI above. Pandora is limited to stations already saved as Sonos favorites. There is no Pandora catalog call. Asking to play anything else throws `SonosError.pandoraLimitedToFavorites`.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/SonosCore` | Models, mock controller, router, 1443 client, UPnP adapter, discovery, presence, Spotify parsing |
| `Sources/SonosDesign` | Colors, type, brass sheen, album-art motifs, sliders, cards, tab bar. SwiftUI, so it compiles on Apple. |
| `App/iOS` | Home, Now Playing, Group Rooms, Browse + Play On |
| `App/watchOS` | Now playing, crown volume arc, "N connected" |
| `project.yml` | XcodeGen project for iOS 17 and watchOS 10 |
| `Tests/SonosCoreTests` | Linux-friendly unit tests |
| `Fixtures/` | Symlinks to the shared JSON fixtures for the future Windows port |

The screens run on `SonosSession`, which sits on `MockSonosController` and the Jason household fixture. Party Mode, Pause All, presets, volume, transport, grouping, and Play On all change that model. `LocalSonosController` is the real path: it discovers, routes, and sends. It is covered by tests with scripted sockets, not by the buttons yet.

## Run it on a Mac

There is no Xcode project checked in. Generate one, then open it.

```bash
brew install xcodegen
xcodegen generate
open SonosController.xcodeproj
```

Pick your team on the SonosController target. Run the iOS app on an iPhone simulator (iOS 17 or newer). The Watch app is embedded. Run SonosWatch on a watchOS 10 simulator to see the crown volume arc.

The Home screen is the rooms overview: Party Mode, Pause All, the Downstairs preset, the session strip on Living Room + Kitchen, the 2-up tiles, the paused Bathroom row, and the tab bar. Now Playing opens from a card or the tab. Group Rooms is the drag-to-build screen. Browse opens on the Play On sheet for Late Night Drive; Cancel shows the Spotify / Pandora switch and the shelves.

### Local network and multicast

`App/iOS/Info.plist` sets:

- `NSLocalNetworkUsageDescription` for speaker discovery and session presence
- `NSBonjourServices` for `_sonos._tcp` and `_jasonssonos._tcp`
- `NSAllowsLocalNetworking` so UPnP on port 1400 is allowed on the LAN

`App/iOS/SonosController.entitlements` includes `com.apple.developer.networking.multicast`. **Apple has to grant that entitlement** before a device build will sign. Bonjour discovery does not need it. SSDP does, because it sends to `239.255.255.250`. Until the entitlement is on the App ID, delete that key from the entitlements file. The app still finds speakers over Bonjour.

Speakers use a self-signed certificate on port 1443. The Apple WebSocket client accepts that certificate for the host it just connected to. Linux Swift cannot override server trust, so the same client compiles there but will not complete a TLS handshake to a speaker. Message encoding is tested on Linux anyway.

## Tests

On this repo, from a machine with Swift 5.9 or newer:

```bash
swift build
swift test
```

That builds `SonosCore` and runs the unit tests. The iOS and watchOS apps are not part of `swift test`. They need Xcode. The design-system sources are in the package and are wrapped in `canImport(SwiftUI)`, so Linux skips the views and still typechecks the core.

## Roadmap

- Point the iOS session at `LocalSonosController` once a household is on the LAN, and keep the mock for previews.
- Subscribe to `groups`, `playback`, `playbackMetadata`, `groupVolume`, and `playerVolume`, and fold events through `HouseholdReducer`.
- Read the Spotify service id and serial from the speaker instead of the defaults.
- Show the real queue, edited only through the UPnP adapter.
- Color the cards from the actual album art instead of the fixture palettes.
- Push household snapshots to the Watch over WatchConnectivity, and use the cloud client only when the phone session is unreachable.
- Port `SonosCore` to C# for an Avalonia client on Windows. Keep `jason-household.json`, the Control API fixtures in the tests, and `ControlRouter`'s matrix as the contract. Discovery on Windows can use the same mDNS query and SSDP packet builders.
