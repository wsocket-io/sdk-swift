/**
 * wSocket Swift SDK — Realtime Pub/Sub client with Presence, History, and Push.
 *
 * Usage:
 *   let client = WSocket(url: "ws://localhost:9001", apiKey: "your-api-key")
 *   client.connect()
 *   let ch = client.pubsub.channel("chat")
 *   ch.subscribe { data, meta in print(data) }
 *   ch.publish(["text": "hello"])
 */

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Types

public struct MessageMeta {
    public let id: String
    public let channel: String
    public let timestamp: Int64
}

public struct PresenceMember {
    public let clientId: String
    public let data: [String: Any]?
    public let joinedAt: Int64
}

public struct HistoryMessage {
    public let id: String
    public let channel: String
    public let data: Any?
    public let publisherId: String
    public let timestamp: Int64
    public let sequence: Int64
}

public struct HistoryResult {
    public let channel: String
    public let messages: [HistoryMessage]
    public let hasMore: Bool
}

public struct WSocketOptions {
    public var autoReconnect: Bool = true
    public var maxReconnectAttempts: Int = 10
    public var reconnectDelay: TimeInterval = 1.0
    public var token: String? = nil
    public var recover: Bool = true

    public init(
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 10,
        reconnectDelay: TimeInterval = 1.0,
        token: String? = nil,
        recover: Bool = true
    ) {
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.token = token
        self.recover = recover
    }
}

// MARK: - Presence

public class Presence {
    private let channelName: String
    private let sendFn: ([String: Any]) -> Void

    private var enterCallbacks: [(PresenceMember) -> Void] = []
    private var leaveCallbacks: [(PresenceMember) -> Void] = []
    private var updateCallbacks: [(PresenceMember) -> Void] = []
    private var membersCallbacks: [([PresenceMember]) -> Void] = []
    private let queue = DispatchQueue(label: "io.wsocket.presence")

    init(channel: String, send: @escaping ([String: Any]) -> Void) {
        self.channelName = channel
        self.sendFn = send
    }

    @discardableResult
    public func enter(data: [String: Any]? = nil) -> Presence {
        sendFn(["action": "presence.enter", "channel": channelName, "data": data as Any])
        return self
    }

    @discardableResult
    public func leave() -> Presence {
        sendFn(["action": "presence.leave", "channel": channelName])
        return self
    }

    @discardableResult
    public func update(data: [String: Any]) -> Presence {
        sendFn(["action": "presence.update", "channel": channelName, "data": data])
        return self
    }

    @discardableResult
    public func get() -> Presence {
        sendFn(["action": "presence.get", "channel": channelName])
        return self
    }

    @discardableResult
    public func onEnter(_ cb: @escaping (PresenceMember) -> Void) -> Presence {
        queue.sync { enterCallbacks.append(cb) }
        return self
    }

    @discardableResult
    public func onLeave(_ cb: @escaping (PresenceMember) -> Void) -> Presence {
        queue.sync { leaveCallbacks.append(cb) }
        return self
    }

    @discardableResult
    public func onUpdate(_ cb: @escaping (PresenceMember) -> Void) -> Presence {
        queue.sync { updateCallbacks.append(cb) }
        return self
    }

    @discardableResult
    public func onMembers(_ cb: @escaping ([PresenceMember]) -> Void) -> Presence {
        queue.sync { membersCallbacks.append(cb) }
        return self
    }

    func handleEvent(action: String, data: [String: Any]) {
        switch action {
        case "presence.enter":
            let m = parseMember(data)
            queue.sync { enterCallbacks }.forEach { $0(m) }
        case "presence.leave":
            let m = parseMember(data)
            queue.sync { leaveCallbacks }.forEach { $0(m) }
        case "presence.update":
            let m = parseMember(data)
            queue.sync { updateCallbacks }.forEach { $0(m) }
        case "presence.members":
            let members = (data["members"] as? [[String: Any]])?.map { parseMember($0) } ?? []
            queue.sync { membersCallbacks }.forEach { $0(members) }
        default: break
        }
    }

    private func parseMember(_ data: [String: Any]) -> PresenceMember {
        PresenceMember(
            clientId: data["clientId"] as? String ?? "",
            data: data["data"] as? [String: Any],
            joinedAt: (data["joinedAt"] as? NSNumber)?.int64Value ?? 0
        )
    }
}

// MARK: - Channel

public class Channel {
    public let name: String
    public let presence: Presence

    private let sendFn: ([String: Any]) -> Void
    private var messageCallbacks: [(Any?, MessageMeta) -> Void] = []
    private var historyCallbacks: [(HistoryResult) -> Void] = []
    private let queue = DispatchQueue(label: "io.wsocket.channel")

    init(name: String, send: @escaping ([String: Any]) -> Void) {
        self.name = name
        self.sendFn = send
        self.presence = Presence(channel: name, send: send)
    }

    @discardableResult
    public func subscribe(_ callback: ((Any?, MessageMeta) -> Void)? = nil) -> Channel {
        if let cb = callback {
            queue.sync { messageCallbacks.append(cb) }
        }
        sendFn(["action": "subscribe", "channel": name])
        return self
    }

    @discardableResult
    public func unsubscribe() -> Channel {
        sendFn(["action": "unsubscribe", "channel": name])
        queue.sync { messageCallbacks.removeAll() }
        return self
    }

    @discardableResult
    public func publish(_ data: Any?, persist: Bool? = nil) -> Channel {
        var msg: [String: Any] = [
            "action": "publish",
            "channel": name,
            "data": data as Any,
            "id": UUID().uuidString
        ]
        if let p = persist { msg["persist"] = p }
        sendFn(msg)
        return self
    }

    @discardableResult
    public func history(limit: Int? = nil, before: Int64? = nil, after: Int64? = nil, direction: String? = nil) -> Channel {
        var opts: [String: Any] = ["action": "history", "channel": name]
        if let l = limit { opts["limit"] = l }
        if let b = before { opts["before"] = b }
        if let a = after { opts["after"] = a }
        if let d = direction { opts["direction"] = d }
        sendFn(opts)
        return self
    }

    @discardableResult
    public func onHistory(_ cb: @escaping (HistoryResult) -> Void) -> Channel {
        queue.sync { historyCallbacks.append(cb) }
        return self
    }

    func handleMessage(data: Any?, meta: MessageMeta) {
        queue.sync { messageCallbacks }.forEach { $0(data, meta) }
    }

    func handleHistory(_ result: HistoryResult) {
        queue.sync { historyCallbacks }.forEach { $0(result) }
    }
}

// MARK: - PubSub Namespace

public class PubSubNamespace {
    private weak var client: WSocket?
    init(client: WSocket) { self.client = client }
    public func channel(_ name: String) -> Channel { client!.channel(name) }
}

// MARK: - Push Client

public class PushClient {
    private let baseUrl: String
    private let token: String
    private let appId: String
    private let session = URLSession.shared

    public init(baseUrl: String, token: String, appId: String) {
        self.baseUrl = baseUrl
        self.token = token
        self.appId = appId
    }

    public func registerAPNs(deviceToken: String, memberId: String, completion: ((Error?) -> Void)? = nil) {
        post("register", body: [
            "memberId": memberId, "platform": "apns",
            "subscription": ["deviceToken": deviceToken]
        ], completion: completion)
    }

    public func registerFCM(deviceToken: String, memberId: String, completion: ((Error?) -> Void)? = nil) {
        post("register", body: [
            "memberId": memberId, "platform": "fcm",
            "subscription": ["deviceToken": deviceToken]
        ], completion: completion)
    }

    public func sendToMember(_ memberId: String, payload: [String: Any], completion: ((Error?) -> Void)? = nil) {
        post("send", body: ["memberId": memberId, "payload": payload], completion: completion)
    }

    public func broadcast(payload: [String: Any], completion: ((Error?) -> Void)? = nil) {
        post("broadcast", body: ["payload": payload], completion: completion)
    }

    private func post(_ path: String, body: [String: Any], completion: ((Error?) -> Void)? = nil) {
        guard let url = URL(string: "\(baseUrl)/api/push/\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.addValue(appId, forHTTPHeaderField: "X-App-Id")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req) { _, _, err in completion?(err) }.resume()
    }
}

// MARK: - WSocket Client

public class WSocket: NSObject, URLSessionWebSocketDelegate {
    private let url: String
    private let apiKey: String
    private let options: WSocketOptions

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var channels: [String: Channel] = [:]
    private var subscribedChannels: Set<String> = []
    private var lastMessageTs: Int64 = 0
    private var reconnectAttempts = 0
    private var isConnected = false
    private let queue = DispatchQueue(label: "io.wsocket.client")

    private var onConnectCallbacks: [() -> Void] = []
    private var onDisconnectCallbacks: [(Int) -> Void] = []
    private var onErrorCallbacks: [(Error) -> Void] = []

    public private(set) lazy var pubsub = PubSubNamespace(client: self)

    public init(url: String, apiKey: String, options: WSocketOptions = WSocketOptions()) {
        self.url = url
        self.apiKey = apiKey
        self.options = options
        super.init()
    }

    @discardableResult
    public func onConnect(_ cb: @escaping () -> Void) -> WSocket {
        onConnectCallbacks.append(cb); return self
    }

    @discardableResult
    public func onDisconnect(_ cb: @escaping (Int) -> Void) -> WSocket {
        onDisconnectCallbacks.append(cb); return self
    }

    @discardableResult
    public func onError(_ cb: @escaping (Error) -> Void) -> WSocket {
        onErrorCallbacks.append(cb); return self
    }

    @discardableResult
    public func connect() -> WSocket {
        var urlStr = url
        urlStr += url.contains("?") ? "&" : "?"
        urlStr += "key=\(apiKey)"
        if let tk = options.token { urlStr += "&token=\(tk)" }

        guard let wsUrl = URL(string: urlStr) else { return self }
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: wsUrl)
        webSocket?.resume()
        listen()
        return self
    }

    public func disconnect() {
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
    }

    public func channel(_ name: String) -> Channel {
        if let ch = channels[name] { return ch }
        let ch = Channel(name: name) { [weak self] msg in self?.send(msg) }
        channels[name] = ch
        return ch
    }

    public func configurePush(baseUrl: String, token: String, appId: String) -> PushClient {
        PushClient(baseUrl: baseUrl, token: token, appId: appId)
    }

    func send(_ msg: [String: Any]) {
        guard isConnected, let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(text)) { _ in }
    }

    private func listen() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self?.handleMessage(text)
                default: break
                }
                self?.listen()
            case .failure(let error):
                self?.isConnected = false
                self?.onErrorCallbacks.forEach { $0(error) }
                self?.maybeReconnect()
            }
        }
    }

    private func handleMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else { return }

        let channelName = json["channel"] as? String

        switch action {
        case "message":
            guard let chName = channelName, let ch = channels[chName] else { return }
            let ts = (json["timestamp"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)
            if ts > lastMessageTs { lastMessageTs = ts }
            let meta = MessageMeta(id: json["id"] as? String ?? "", channel: chName, timestamp: ts)
            ch.handleMessage(data: json["data"], meta: meta)

        case "subscribed":
            if let ch = channelName { subscribedChannels.insert(ch) }

        case "unsubscribed":
            if let ch = channelName { subscribedChannels.remove(ch) }

        case "history":
            guard let chName = channelName, let ch = channels[chName] else { return }
            let msgs = (json["messages"] as? [[String: Any]])?.map { m in
                HistoryMessage(
                    id: m["id"] as? String ?? "", channel: chName,
                    data: m["data"], publisherId: m["publisherId"] as? String ?? "",
                    timestamp: (m["timestamp"] as? NSNumber)?.int64Value ?? 0,
                    sequence: (m["sequence"] as? NSNumber)?.int64Value ?? 0
                )
            } ?? []
            ch.handleHistory(HistoryResult(channel: chName, messages: msgs, hasMore: json["hasMore"] as? Bool ?? false))

        case "presence.enter", "presence.leave", "presence.update", "presence.members":
            guard let chName = channelName, let ch = channels[chName] else { return }
            ch.presence.handleEvent(action: action, data: json)

        case "error":
            let errMsg = json["error"] as? String ?? "Unknown error"
            onErrorCallbacks.forEach { $0(NSError(domain: "WSocket", code: -1, userInfo: [NSLocalizedDescriptionKey: errMsg])) }

        default: break
        }
    }

    // MARK: URLSessionWebSocketDelegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        isConnected = true
        reconnectAttempts = 0

        if options.recover && !subscribedChannels.isEmpty && lastMessageTs > 0 {
            let resumeData: [String: Any] = ["channels": Array(subscribedChannels), "since": lastMessageTs]
            if let jsonData = try? JSONSerialization.data(withJSONObject: resumeData),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                let token = Data(jsonStr.utf8).base64EncodedString()
                send(["action": "resume", "token": token])
            }
        } else {
            subscribedChannels.forEach { ch in
                send(["action": "subscribe", "channel": ch])
            }
        }

        DispatchQueue.main.async { self.onConnectCallbacks.forEach { $0() } }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        DispatchQueue.main.async { self.onDisconnectCallbacks.forEach { $0(closeCode.rawValue) } }
        maybeReconnect()
    }

    private func maybeReconnect() {
        guard options.autoReconnect, reconnectAttempts < options.maxReconnectAttempts else { return }
        reconnectAttempts += 1
        let delay = options.reconnectDelay * Double(reconnectAttempts)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            self.connect()
        }
    }
}
