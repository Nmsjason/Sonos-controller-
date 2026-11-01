import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum UDPSocket {
    static func exchange(host: String, port: UInt16, payload: Data, timeout: TimeInterval, maxPackets: Int = 8) throws -> [Data] {
        let fd = socket(AF_INET, datagramType, 0)
        if fd < 0 {
            throw SonosError.network("socket failed (\(errno))")
        }
        defer { _ = close(fd) }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval()
        tv.tv_sec = time_t(timeout)
        tv.tv_usec = suseconds_t((timeout - Double(Int(timeout))) * 1_000_000)
        _ = withUnsafePointer(to: &tv) { ptr in
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            throw SonosError.network("Could not parse \(host)")
        }

        let sent: Int = payload.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            throw SonosError.network("sendto failed (\(errno))")
        }

        var packets: [Data] = []
        var buffer = [UInt8](repeating: 0, count: 8192)
        while packets.count < maxPackets {
            let count: Int = buffer.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress, raw.count, 0)
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT { break }
                throw SonosError.network("recv failed (\(errno))")
            }
            if count == 0 { break }
            packets.append(Data(buffer.prefix(count)))
        }
        return packets
    }

    /// Confirms the datagram path on the loopback interface. Discovery itself uses multicast.
    static func loopbackSelfTest() throws {
        let server = socket(AF_INET, datagramType, 0)
        if server < 0 { throw SonosError.network("loopback socket failed") }
        defer { _ = close(server) }

        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0
        bindAddr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(server, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 { throw SonosError.network("loopback bind failed (\(errno))") }

        var got = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(server, sa, &length)
            }
        }
        if named != 0 { throw SonosError.network("getsockname failed") }
        let port = UInt16(bigEndian: got.sin_port)

        let lock = NSLock()
        var reply = Data()
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 64)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    buffer.withUnsafeMutableBytes { raw in
                        recvfrom(server, raw.baseAddress, raw.count, 0, sa, &sourceLength)
                    }
                }
            }
            guard count > 0 else { return }
            let response = Data("pong".utf8)
            _ = response.withUnsafeBytes { raw in
                withUnsafePointer(to: &source) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(server, raw.baseAddress, raw.count, 0, sa, sourceLength)
                    }
                }
            }
            lock.lock()
            reply = Data(buffer.prefix(count))
            lock.unlock()
        }
        thread.start()
        Thread.sleep(forTimeInterval: 0.05)
        let packets = try exchange(host: "127.0.0.1", port: port, payload: Data("ping".utf8), timeout: 1, maxPackets: 1)
        thread.cancel()
        guard packets.first == Data("pong".utf8) else {
            throw SonosError.network("loopback reply missing")
        }
        lock.lock()
        let seen = reply
        lock.unlock()
        guard seen == Data("ping".utf8) else {
            throw SonosError.network("loopback request missing")
        }
    }
}

private let datagramType: Int32 = {
    #if canImport(Darwin)
    return SOCK_DGRAM
    #else
    return Int32(SOCK_DGRAM.rawValue)
    #endif
}()
