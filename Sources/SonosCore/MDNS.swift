import Foundation

struct DNSNameReader {
    var data: Data
    var index: Int

    mutating func u16() throws -> UInt16 {
        guard index + 2 <= data.count else { throw SonosError.malformed("DNS truncated") }
        let value = (UInt16(data[index]) << 8) | UInt16(data[index + 1])
        index += 2
        return value
    }

    mutating func u32() throws -> UInt32 {
        let high = try u16()
        let low = try u16()
        return (UInt32(high) << 16) | UInt32(low)
    }

    mutating func readName() throws -> String {
        var labels: [String] = []
        var position = index
        var endOfName: Int?
        var jumps = 0
        while true {
            guard position < data.count else { throw SonosError.malformed("DNS name ran off the packet") }
            let length = Int(data[position])
            if length == 0 {
                position += 1
                if endOfName == nil { endOfName = position }
                break
            }
            if length & 0xC0 == 0xC0 {
                guard position + 1 < data.count else { throw SonosError.malformed("DNS pointer truncated") }
                if endOfName == nil { endOfName = position + 2 }
                let offset = ((length & 0x3F) << 8) | Int(data[position + 1])
                guard offset < data.count else { throw SonosError.malformed("DNS pointer out of range") }
                position = offset
                jumps += 1
                if jumps > 12 { throw SonosError.malformed("DNS pointer loop") }
                continue
            }
            guard length < 64 else { throw SonosError.malformed("DNS label too long") }
            position += 1
            guard position + length <= data.count else { throw SonosError.malformed("DNS label truncated") }
            labels.append(String(decoding: data[position..<(position + length)], as: UTF8.self))
            position += length
        }
        index = endOfName ?? position
        return labels.joined(separator: ".")
    }
}

struct DNSWriter {
    var data = Data()

    mutating func u8(_ value: UInt8) { data.append(value) }

    mutating func u16(_ value: UInt16) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xFF))
    }

    mutating func u32(_ value: UInt32) {
        u16(UInt16(value >> 16))
        u16(UInt16(value & 0xFFFF))
    }

    mutating func name(_ value: String) throws {
        let labels = value.split(separator: ".").map(String.init)
        for label in labels {
            let bytes = Array(label.utf8)
            guard bytes.count < 64 else { throw SonosError.malformed("DNS label too long") }
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0)
    }

    mutating func bytes(_ value: Data) { data.append(value) }
}

public struct DNSSRV: Equatable, Sendable {
    public var priority: UInt16
    public var weight: UInt16
    public var port: UInt16
    public var target: String
}

public struct DNSRecord: Equatable, Sendable {
    public var name: String
    public var type: UInt16
    public var ttl: UInt32
    public var ptr: String?
    public var txt: [String: String]?
    public var address: String?
    public var srv: DNSSRV?
}

public struct MDNSService: Equatable, Sendable {
    public var instance: String
    public var host: String
    public var port: Int
    public var addresses: [String]
    public var txt: [String: String]

    public init(instance: String, host: String, port: Int, addresses: [String], txt: [String: String]) {
        self.instance = instance
        self.host = host
        self.port = port
        self.addresses = addresses
        self.txt = txt
    }
}

public struct MDNSMessage: Equatable, Sendable {
    public var records: [DNSRecord]

    public static let ptrType: UInt16 = 12
    public static let txtType: UInt16 = 16
    public static let aType: UInt16 = 1
    public static let srvType: UInt16 = 33
    public static let host = "224.0.0.251"
    public static let port: UInt16 = 5353
    public static let sonosService = "_sonos._tcp.local"
    public static let presenceService = "_jasonssonos._tcp.local"

    public static func query(name: String) throws -> Data {
        var writer = DNSWriter()
        writer.u16(0)
        writer.u16(0)
        writer.u16(1)
        writer.u16(0)
        writer.u16(0)
        writer.u16(0)
        try writer.name(name)
        writer.u16(ptrType)
        writer.u16(0x8001)
        return writer.data
    }

    public static func parse(_ data: Data) throws -> MDNSMessage {
        guard data.count >= 12 else { throw SonosError.malformed("DNS header truncated") }
        var reader = DNSNameReader(data: data, index: 0)
        _ = try reader.u16()
        _ = try reader.u16()
        let questions = Int(try reader.u16())
        let answers = Int(try reader.u16())
        let authorities = Int(try reader.u16())
        let additional = Int(try reader.u16())
        for _ in 0..<questions {
            _ = try reader.readName()
            _ = try reader.u16()
            _ = try reader.u16()
        }
        var records: [DNSRecord] = []
        for _ in 0..<(answers + authorities + additional) {
            records.append(try readRecord(&reader))
        }
        return MDNSMessage(records: records)
    }

    public func services(matching service: String) -> [MDNSService] {
        let suffix = service.hasSuffix(".local") ? service : service + ".local"
        let instances = records.filter { $0.type == MDNSMessage.ptrType && $0.name == suffix }.compactMap(\.ptr)
        return instances.map { instance in
            let srv = records.first { $0.name == instance && $0.type == MDNSMessage.srvType }?.srv
            let txt = records.first { $0.name == instance && $0.type == MDNSMessage.txtType }?.txt ?? [:]
            let host = srv?.target ?? ""
            let addresses = records.filter { $0.name == host && $0.type == MDNSMessage.aType }.compactMap(\.address)
            return MDNSService(
                instance: instance,
                host: host,
                port: Int(srv?.port ?? 1443),
                addresses: addresses,
                txt: txt
            )
        }
    }

    public static func encodeTXT(_ pairs: [String: String]) -> Data {
        var data = Data()
        for key in pairs.keys.sorted() {
            let entry = Array("\(key)=\(pairs[key] ?? "")".utf8)
            let length = min(255, entry.count)
            data.append(UInt8(length))
            data.append(contentsOf: entry.prefix(length))
        }
        return data
    }

    public static func decodeTXT(_ data: Data) -> [String: String] {
        var pairs: [String: String] = [:]
        var index = 0
        while index < data.count {
            let length = Int(data[index])
            index += 1
            guard index + length <= data.count else { break }
            let raw = String(decoding: data[index..<(index + length)], as: UTF8.self)
            index += length
            if let split = raw.firstIndex(of: "=") {
                pairs[String(raw[..<split])] = String(raw[raw.index(after: split)...])
            } else if !raw.isEmpty {
                pairs[raw] = ""
            }
        }
        return pairs
    }
}

private func readRecord(_ reader: inout DNSNameReader) throws -> DNSRecord {
    let name = try reader.readName()
    let type = try reader.u16()
    _ = try reader.u16()
    let ttl = try reader.u32()
    let length = Int(try reader.u16())
    guard reader.index + length <= reader.data.count else { throw SonosError.malformed("DNS rdata truncated") }
    let start = reader.index
    let rdata = reader.data[start..<(start + length)]
    var record = DNSRecord(name: name, type: type, ttl: ttl, ptr: nil, txt: nil, address: nil, srv: nil)
    switch type {
    case MDNSMessage.ptrType:
        record.ptr = try reader.readName()
    case MDNSMessage.txtType:
        record.txt = MDNSMessage.decodeTXT(Data(rdata))
        reader.index = start + length
    case MDNSMessage.aType:
        if rdata.count == 4 {
            record.address = rdata.map(String.init).joined(separator: ".")
        }
        reader.index = start + length
    case MDNSMessage.srvType:
        guard length >= 7 else { throw SonosError.malformed("DNS SRV truncated") }
        var local = DNSNameReader(data: reader.data, index: start)
        let priority = (UInt16(reader.data[start]) << 8) | UInt16(reader.data[start + 1])
        let weight = (UInt16(reader.data[start + 2]) << 8) | UInt16(reader.data[start + 3])
        let port = (UInt16(reader.data[start + 4]) << 8) | UInt16(reader.data[start + 5])
        local.index = start + 6
        let target = try local.readName()
        record.srv = DNSSRV(priority: priority, weight: weight, port: port, target: target)
        reader.index = start + length
    default:
        reader.index = start + length
    }
    return record
}
