import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

public struct LocalWebSocketConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var subprotocol: String
    /// Speakers present a self-signed certificate. Apple accepts it for the connected host only.
    /// swift-corelibs-foundation cannot override server trust, so this flag is a no-op on Linux.
    public var acceptSelfSignedCertificates: Bool

    public init(
        apiKey: String = ControlAPI.localAPIKey,
        subprotocol: String = ControlAPI.subprotocol,
        acceptSelfSignedCertificates: Bool = true
    ) {
        self.apiKey = apiKey
        self.subprotocol = subprotocol
        self.acceptSelfSignedCertificates = acceptSelfSignedCertificates
    }

    public static let localDefault = LocalWebSocketConfiguration()
}

public protocol RealtimeSending: Sendable {
    func connect(url: URL) async throws
    func send(_ message: ControlMessage) async throws
    func receive() async throws -> ControlMessage
    func close() async
}

public protocol SOAPSending: Sendable {
    func send(_ action: UPnPAction) async throws -> Data
}

public protocol CloudSending: Sendable {
    func send(_ call: CloudCall, token: String) async throws -> Data
}

/// WebSocket client for `wss://<speaker>:1443/websocket/api`.
public final class LocalWebSocketClient: NSObject, URLSessionWebSocketDelegate, RealtimeSending, @unchecked Sendable {
    public let configuration: LocalWebSocketConfiguration
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var trustedHosts: Set<String> = []
    private var liveSession: URLSession?
    public private(set) var acceptedProtocol: String?

    public override init() {
        self.configuration = .localDefault
        super.init()
    }

    public init(configuration: LocalWebSocketConfiguration) {
        self.configuration = configuration
        super.init()
    }

    private func makeSession() -> URLSession {
        if let liveSession { return liveSession }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        liveSession = session
        return session
    }

    public func connect(url: URL) async throws {
        if let host = url.host {
            lock.lock()
            trustedHosts.insert(host)
            lock.unlock()
        }
        var request = URLRequest(url: url)
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Sonos-Api-Key")
        request.setValue(configuration.subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = makeSession().webSocketTask(with: request)
        lock.lock()
        self.task = task
        lock.unlock()
        task.resume()
    }

    public func send(_ message: ControlMessage) async throws {
        let data = try message.encoded()
        guard let text = String(data: data, encoding: .utf8) else {
            throw SonosError.malformed("Control frame was not UTF-8")
        }
        guard let task = currentTask() else { throw SonosError.notConnected }
        try await task.send(.string(text))
    }

    public func receive() async throws -> ControlMessage {
        guard let task = currentTask() else { throw SonosError.notConnected }
        let message = try await task.receive()
        switch message {
        case let .string(text):
            guard let data = text.data(using: .utf8) else { throw SonosError.malformed("Empty websocket text") }
            return try ControlMessage.decode(data)
        case let .data(data):
            return try ControlMessage.decode(data)
        @unknown default:
            throw SonosError.malformed("Unsupported websocket frame")
        }
    }

    public func close() async {
        currentTask()?.cancel(with: .normalClosure, reason: nil)
        lock.lock()
        task = nil
        lock.unlock()
    }

    private func currentTask() -> URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        acceptedProtocol = `protocol`
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {}

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        #if canImport(Security)
        let host = challenge.protectionSpace.host
        lock.lock()
        let trusted = trustedHosts.contains(host)
        lock.unlock()
        if configuration.acceptSelfSignedCertificates,
           trusted,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        #endif
        return (.performDefaultHandling, nil)
    }
}

public struct LiveSOAPClient: SOAPSending {
    public init() {}

    public func send(_ action: UPnPAction) async throws -> Data {
        var request = URLRequest(url: action.url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(action.soapAction, forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(action.soapEnvelope().utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SonosError.soapFault("HTTP \(http.statusCode) \(body)")
        }
        return data
    }
}

public enum CloudEndpoint {
    public static func url(base: URL, path: String) -> URL? {
        let root = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: root + suffix)
    }
}

public struct LiveCloudClient: CloudSending {
    public var baseURL: URL

    public init(baseURL: URL = URL(string: "https://api.ws.sonos.com/control/api/v1")!) {
        self.baseURL = baseURL
    }

    public func send(_ call: CloudCall, token: String) async throws -> Data {
        guard let url = CloudEndpoint.url(base: baseURL, path: call.path) else {
            throw SonosError.malformed("Bad cloud path \(call.path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = call.method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = call.body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SonosError.commandFailed("Cloud HTTP \(http.statusCode)")
        }
        return data
    }
}

public final class LocalSonosController: SonosControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var state: HouseholdSnapshot
    private var context: ControlContext
    private let builder: LocalCommandBuilder
    private let realtime: any RealtimeSending
    private let soap: any SOAPSending
    private let cloud: any CloudSending
    private let cloudToken: String?
    private var continuations: [UUID: AsyncStream<HouseholdSnapshot>.Continuation] = [:]

    public init(
        snapshot: HouseholdSnapshot,
        context: ControlContext,
        realtime: any RealtimeSending,
        soap: any SOAPSending,
        cloud: any CloudSending = LiveCloudClient(),
        cloudToken: String? = nil,
        account: SonosMusicServiceAccount = SonosMusicServiceAccount()
    ) {
        self.state = snapshot
        self.context = context
        self.realtime = realtime
        self.soap = soap
        self.cloud = cloud
        self.cloudToken = cloudToken
        self.builder = LocalCommandBuilder(account: account)
    }

    public func update(context: ControlContext) {
        lock.lock()
        self.context = context
        lock.unlock()
    }

    public func apply(_ message: ControlMessage) {
        lock.lock()
        state.household = HouseholdReducer.apply(message, to: state.household)
        let snapshot = state
        let continuations = Array(self.continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(snapshot) }
    }

    public func snapshot() async -> HouseholdSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func updates() async -> AsyncStream<HouseholdSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let current = state
            lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    public func perform(_ command: ControllerCommand) async throws {
        let (snapshot, context) = current()
        let calls = try builder.prepare(command, household: snapshot.household, context: context)
        for call in calls {
            switch call {
            case let .webSocket(message):
                try await realtime.send(message)
            case let .upnp(action):
                _ = try await soap.send(action)
            case let .cloud(cloudCall):
                guard let cloudToken else { throw SonosError.cloudUnavailable }
                _ = try await cloud.send(cloudCall, token: cloudToken)
            case .phoneRelay:
                break
            }
        }
    }

    private func current() -> (HouseholdSnapshot, ControlContext) {
        lock.lock()
        defer { lock.unlock() }
        return (state, context)
    }
}
