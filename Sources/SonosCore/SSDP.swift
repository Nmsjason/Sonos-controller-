import Foundation

public struct SSDPResponse: Equatable, Sendable {
    public var location: URL
    public var usn: String
    public var server: String
    public var searchTarget: String
    public var householdId: String?
    public var uuid: String

    public static let multicastHost = "239.255.255.250"
    public static let port: UInt16 = 1900
    public static let searchTarget = "urn:schemas-upnp-org:device:ZonePlayer:1"

    public static func searchRequest(mx: Int = 1) -> Data {
        let text = "M-SEARCH * HTTP/1.1\r\n"
            + "HOST: 239.255.255.250:1900\r\n"
            + "MAN: \"ssdp:discover\"\r\n"
            + "MX: \(mx)\r\n"
            + "ST: \(searchTarget)\r\n"
            + "\r\n"
        return Data(text.utf8)
    }

    public static func parse(_ data: Data) -> SSDPResponse? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let headers = headerMap(text)
        guard let locationRaw = headers["location"], let location = URL(string: locationRaw) else { return nil }
        let usn = headers["usn"] ?? ""
        let server = headers["server"] ?? ""
        let st = headers["st"] ?? ""
        guard locationRaw.contains(":1400") else { return nil }
        guard usn.contains("RINCON_") || server.localizedCaseInsensitiveContains("Sonos") else { return nil }
        let uuid = extractUUID(usn) ?? extractUUID(locationRaw) ?? ""
        guard !uuid.isEmpty else { return nil }
        let household = headers["x-rincon-household"] ?? headers["household.smart_speaker.audio"]
        return SSDPResponse(location: location, usn: usn, server: server, searchTarget: st, householdId: household, uuid: uuid)
    }

    private static func headerMap(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return headers
    }

    private static func extractUUID(_ raw: String) -> String? {
        guard let range = raw.range(of: "RINCON_[A-Za-z0-9]+", options: .regularExpression) else { return nil }
        return String(raw[range])
    }
}

public struct DeviceDescription: Equatable, Sendable {
    public var roomName: String
    public var udn: String
    public var modelName: String?
    public var friendlyName: String?

    public static func parse(_ xml: String) -> DeviceDescription? {
        guard let room = firstTag("roomName", in: xml) ?? firstTag("friendlyName", in: xml) else { return nil }
        let udnRaw = firstTag("UDN", in: xml) ?? firstTag("udn", in: xml) ?? ""
        let udn = udnRaw.replacingOccurrences(of: "uuid:", with: "")
        return DeviceDescription(
            roomName: room,
            udn: udn,
            modelName: firstTag("modelName", in: xml),
            friendlyName: firstTag("friendlyName", in: xml)
        )
    }

    private static func firstTag(_ name: String, in xml: String) -> String? {
        let pattern = "<\(name)>([^<]*)</\(name)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: xml) else { return nil }
        let value = String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
