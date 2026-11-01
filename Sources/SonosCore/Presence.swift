import Foundation

/// LAN presence for "Users joined to session".
///
/// Each iPhone advertises `_jasonssonos._tcp` while it is controlling a group. Other phones browse
/// the same service and filter on household id and group id. Bonjour is used instead of Multipeer
/// Connectivity so a future Windows client can see the same records without an Apple-only pairing step.
/// Until a phone is browsing, the controller publishes `MockSessionPresence`.
public enum PresenceService {
    public static let type = "_jasonssonos._tcp"
    public static let fullName = "_jasonssonos._tcp.local"
    public static let version = "1"
}

public struct PresenceAdvertisement: Equatable, Sendable {
    public var peer: SessionPeer
    public var householdId: String

    public init(peer: SessionPeer, householdId: String) {
        self.peer = peer
        self.householdId = householdId
    }

    public func txt() -> [String: String] {
        var pairs = [
            "v": PresenceService.version,
            "id": peer.id,
            "n": peer.name,
            "h": householdId,
            "p": peer.presence.rawValue,
        ]
        if let groupId = peer.groupId {
            pairs["g"] = groupId
        }
        return pairs
    }

    public static func parse(txt: [String: String]) -> PresenceAdvertisement? {
        guard txt["v"] == PresenceService.version,
              let id = txt["id"],
              let name = txt["n"],
              let householdId = txt["h"] else {
            return nil
        }
        let presence = PeerPresence(rawValue: txt["p"] ?? "") ?? .active
        return PresenceAdvertisement(
            peer: SessionPeer(id: id, name: name, groupId: txt["g"], presence: presence),
            householdId: householdId
        )
    }
}

public protocol SessionPresence: Sendable {
    func peers() async -> [SessionPeer]
}

public struct MockSessionPresence: SessionPresence {
    public var advertised: [SessionPeer]

    public init(peers: [SessionPeer]) {
        self.advertised = peers
    }

    public func peers() async -> [SessionPeer] { advertised }
}

#if canImport(Network)
import Network

/// Browses `_jasonssonos._tcp` with `NWBrowser`, which does not need the multicast entitlement.
public final class BonjourSessionPresence: SessionPresence, @unchecked Sendable {
    private let lock = NSLock()
    private var found: [SessionPeer] = []
    private var browser: NWBrowser?

    public init() {}

    public func start() {
        let browser = NWBrowser(for: .bonjour(type: PresenceService.type, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.absorb(results)
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    public func peers() async -> [SessionPeer] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    private func absorb(_ results: Set<NWBrowser.Result>) {
        var peers: [SessionPeer] = []
        for result in results {
            guard case let .bonjour(record) = result.metadata else { continue }
            var pairs: [String: String] = [:]
            for key in ["v", "id", "n", "h", "p", "g"] {
                if let value = record[key] {
                    pairs[key] = value
                }
            }
            if let advertisement = PresenceAdvertisement.parse(txt: pairs) {
                peers.append(advertisement.peer)
            }
        }
        lock.lock()
        found = peers
        lock.unlock()
    }
}

/// Advertises this phone on `_jasonssonos._tcp`. The listener is only started on Apple platforms.
public final class BonjourPresenceAdvertiser: @unchecked Sendable {
    private var listener: NWListener?

    public init() {}

    public func start(_ advertisement: PresenceAdvertisement) throws {
        let listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(
            name: advertisement.peer.name,
            type: PresenceService.type,
            txtRecord: NWTXTRecord(advertisement.txt())
        )
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}
#endif
