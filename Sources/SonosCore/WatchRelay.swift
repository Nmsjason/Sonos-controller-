import Foundation

/// JSON envelope carried across WatchConnectivity. The phone applies `ControlRouter` after it arrives.
public struct WatchEnvelope: Codable, Equatable, Sendable {
    public var command: ControllerCommand

    public init(command: ControllerCommand) {
        self.command = command
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> WatchEnvelope {
        try JSONDecoder().decode(WatchEnvelope.self, from: data)
    }
}

#if canImport(WatchConnectivity)
import WatchConnectivity

public final class WatchPhoneBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchPhoneBridge()

    public var onCommand: (@Sendable (ControllerCommand) -> Void)?

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    public func send(_ command: ControllerCommand) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard let data = try? WatchEnvelope(command: command).encoded() else { return }
        if session.isReachable {
            session.sendMessage(["command": data], replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(["command": data])
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo)
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif

    private func deliver(_ payload: [String: Any]) {
        guard let data = payload["command"] as? Data, let envelope = try? WatchEnvelope.decode(data) else { return }
        onCommand?(envelope.command)
    }
}
#endif
