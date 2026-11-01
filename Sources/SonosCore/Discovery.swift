import Foundation
#if canImport(Network)
import Network
#endif

public protocol ServiceBrowser: Sendable {
    func browse(service: String, timeout: TimeInterval) async throws -> [MDNSService]
}

public protocol SSDPBrowsing: Sendable {
    func search(timeout: TimeInterval) async throws -> [SSDPResponse]
}

public struct LiveMDNSBrowser: ServiceBrowser {
    public init() {}

    public func browse(service: String, timeout: TimeInterval) async throws -> [MDNSService] {
        let name = service.hasSuffix(".local") ? service : service + ".local"
        let query = try MDNSMessage.query(name: name)
        let packets = try UDPSocket.exchange(
            host: MDNSMessage.host,
            port: MDNSMessage.port,
            payload: query,
            timeout: timeout,
            maxPackets: 32
        )
        var services: [MDNSService] = []
        var seen = Set<String>()
        for packet in packets {
            let parsed = try? MDNSMessage.parse(packet)
            for service in parsed?.services(matching: name) ?? [] where seen.insert(service.instance).inserted {
                services.append(service)
            }
        }
        return services
    }
}

#if canImport(Network)
/// Bonjour browse via Network.framework. This is the iOS path: it does not need the multicast entitlement.
/// The Linux path is `LiveMDNSBrowser`, which sends a unicast-response mDNS query.
public struct NetworkBonjourBrowser: ServiceBrowser {
    public init() {}

    public func browse(service: String, timeout: TimeInterval) async throws -> [MDNSService] {
        let type = service.hasSuffix(".local") ? String(service.dropLast(6)) : service
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
        let box = BonjourBox()
        browser.browseResultsChangedHandler = { results, _ in
            box.latest = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                var txt: [String: String] = [:]
                if case let .bonjour(record) = result.metadata {
                    for key in ["uuid", "location", "hhid", "protovers", "variant", "info"] {
                        if let value = record[key] {
                            txt[key] = value
                        }
                    }
                }
                let location = txt["location"].flatMap(URL.init(string:))
                let host = location?.host ?? ""
                return MDNSService(
                    instance: name.contains("._") ? name : "\(name).\(type).local",
                    host: host,
                    port: 1443,
                    addresses: host.isEmpty ? [] : [host],
                    txt: txt
                )
            }
        }
        browser.start(queue: .global(qos: .utility))
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        browser.cancel()
        return box.latest
    }
}

private final class BonjourBox: @unchecked Sendable {
    var latest: [MDNSService] = []
}
#endif

public struct LiveSSDPBrowser: SSDPBrowsing {
    public init() {}

    public func search(timeout: TimeInterval) async throws -> [SSDPResponse] {
        let packets = try UDPSocket.exchange(
            host: SSDPResponse.multicastHost,
            port: SSDPResponse.port,
            payload: SSDPResponse.searchRequest(),
            timeout: timeout,
            maxPackets: 32
        )
        var speakers: [SSDPResponse] = []
        var seen = Set<String>()
        for packet in packets {
            if let response = SSDPResponse.parse(packet), seen.insert(response.uuid).inserted {
                speakers.append(response)
            }
        }
        return speakers
    }
}

extension DiscoveredSpeaker {
    public init?(mdns service: MDNSService) {
        let uuid = service.txt["uuid"] ?? service.instance.split(separator: "@").first.map(String.init) ?? ""
        guard uuid.contains("RINCON_") else { return nil }
        let location = service.txt["location"].flatMap(URL.init(string:))
        let host = service.addresses.first ?? location?.host ?? service.host
        guard !host.isEmpty else { return nil }
        self.init(
            id: uuid,
            name: service.instance.split(separator: "@").dropFirst().first.map { String($0).split(separator: ".").first.map(String.init) ?? String($0) },
            householdId: service.txt["hhid"],
            host: host,
            websocketPort: service.port == 0 ? 1443 : service.port,
            location: location,
            source: .bonjour
        )
    }

    public init?(ssdp response: SSDPResponse) {
        guard let host = response.location.host else { return nil }
        self.init(
            id: response.uuid,
            name: nil,
            householdId: response.householdId,
            host: host,
            websocketPort: 1443,
            location: response.location,
            source: .ssdp
        )
    }
}

public struct SpeakerDiscovery: Sendable {
    private let mdns: any ServiceBrowser
    private let ssdp: any SSDPBrowsing

    public init(mdns: (any ServiceBrowser)? = nil, ssdp: (any SSDPBrowsing)? = nil) {
        #if canImport(Network)
        self.mdns = mdns ?? NetworkBonjourBrowser()
        #else
        self.mdns = mdns ?? LiveMDNSBrowser()
        #endif
        self.ssdp = ssdp ?? LiveSSDPBrowser()
    }

    /// Bonjour `_sonos._tcp` first. SSDP runs only when Bonjour returns nothing.
    /// SSDP needs the iOS multicast entitlement; Bonjour does not.
    public func discover(timeout: TimeInterval = 2) async throws -> (speakers: [DiscoveredSpeaker], usedSSDPFallback: Bool) {
        let services = try await mdns.browse(service: MDNSMessage.sonosService, timeout: timeout)
        let bonjour = dedupe(services.compactMap(DiscoveredSpeaker.init(mdns:)))
        if !bonjour.isEmpty {
            return (bonjour, false)
        }
        let responses = try await ssdp.search(timeout: timeout)
        return (dedupe(responses.compactMap(DiscoveredSpeaker.init(ssdp:))), true)
    }

    private func dedupe(_ speakers: [DiscoveredSpeaker]) -> [DiscoveredSpeaker] {
        var seen = Set<String>()
        return speakers.filter { seen.insert($0.id).inserted }
    }
}
