import Foundation
import Combine

/// 一条来自中继的入站消息（原始信封）
struct IncomingEnvelope {
    let messageId: String
    let from: String          // 发送方 deviceId（智能体）
    let fromName: String
    let type: String          // "agent" 或其它
    let payload: [String: Any]
    let receivedAt: Date
}

/// 中继传输层：与 `relay_server.py`（kai-fan-le-helper 内置）协议完全兼容。
///
///   POST /relay/register  -> relayToken
///   POST /relay/send      -> 发送
///   GET  /relay/poll      -> 长轮询
///   POST /relay/ack       -> 确认
///   GET  /relay/devices   -> 在线设备
///   POST /relay/unregister-> 注销
final class RelayTransport: ObservableObject {
    enum State: String {
        case idle, connecting, connected, error
        var display: String {
            switch self {
            case .idle: return "未连接"
            case .connecting: return "连接中…"
            case .connected: return "已连接"
            case .error: return "异常"
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?

    /// 大文件上传服务器（可选）。为空时仅支持内联小附件。
    var fileServerURL: String = ""

    /// 收到消息回调（Store 注入），携带 messageId 与原始信封
    var onIncoming: ((IncomingEnvelope) -> Void)?

    private var baseURL: String = ""
    private var token: String = ""
    private var deviceId: String = ""
    private var deviceName: String = ""
    private var barkKey: String = ""
    private var loopTask: Task<Void, Never>?
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 35
        cfg.timeoutIntervalForResource = 60
        session = URLSession(configuration: cfg)
    }

    var isConnected: Bool { state == .connected }
    var currentDeviceId: String { deviceId }

    // MARK: - 启停

    func start(url: String, devId: String, devName: String, barkKey: String = "") {
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty, !devId.isEmpty else {
            stop()
            return
        }
        if loopTask != nil, baseURL == u, deviceId == devId, self.barkKey == barkKey {
            return
        }
        stop()
        baseURL = u.hasSuffix("/") ? String(u.dropLast()) : u
        deviceId = devId
        deviceName = devName
        self.barkKey = barkKey
        state = .connecting
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        if !token.isEmpty, !baseURL.isEmpty {
            let t = token
            let base = baseURL
            Task.detached {
                guard let url = URL(string: base + "/relay/unregister") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 5
                req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
                _ = try? await URLSession.shared.data(for: req)
            }
        }
        loopTask?.cancel()
        loopTask = nil
        token = ""
        state = .idle
    }

    // MARK: - 主循环

    private func runLoop() async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            do {
                if token.isEmpty {
                    await setState(.connecting)
                    let t = try await register()
                    guard let t = t, !t.isEmpty else {
                        await setState(.error, "注册失败")
                        backoff = await sleepBackoff(backoff)
                        continue
                    }
                    token = t
                    await setState(.connected, nil)
                    backoff = 1
                }

                let envelopes = try await poll()
                backoff = 1
                await setState(.connected, nil)
                for e in envelopes {
                    await MainActor.run { self.onIncoming?(e) }
                }
            } catch {
                token = ""
                await setState(.error, error.localizedDescription)
                backoff = await sleepBackoff(backoff)
            }
        }
    }

    @MainActor private func setState(_ s: State, _ err: String? = nil) {
        state = s
        if err != nil { lastError = err }
        else if s == .connected { lastError = nil }
    }

    private func sleepBackoff(_ b: UInt64) async -> UInt64 {
        try? await Task.sleep(nanoseconds: b * 1_000_000_000)
        return min(b * 2, 30)
    }

    // MARK: - HTTP 基础

    private func makeRequest(_ path: String, method: String, auth: Bool) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth && !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func register() async throws -> String? {
        guard var req = makeRequest("/relay/register", method: "POST", auth: false) else { return nil }
        var body: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": deviceName,
            "platform": "ios",
            "pushMode": "poll",
            "version": AppConstants.version
        ]
        if !barkKey.isEmpty { body["barkKey"] = barkKey }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ok"] as? Bool) == true else { return nil }
        return obj["relayToken"] as? String
    }

    private func poll() async throws -> [IncomingEnvelope] {
        guard let req = makeRequest("/relay/poll?timeout=25", method: "GET", auth: true) else { return [] }
        let (data, _) = try await session.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let arr = obj["messages"] as? [[String: Any]] else { return [] }
        var out: [IncomingEnvelope] = []
        for m in arr {
            guard let mid = m["messageId"] as? String else { continue }
            let from = (m["from"] as? String) ?? ""
            let fromName = (m["fromName"] as? String) ?? "智能体"
            let type = (m["type"] as? String) ?? "agent"
            let payload = (m["payload"] as? [String: Any]) ?? [:]
            let receivedAt = ISO8601DateFormatter().date(from: (m["receivedAt"] as? String) ?? "") ?? Date()
            out.append(IncomingEnvelope(messageId: mid, from: from, fromName: fromName,
                                        type: type, payload: payload, receivedAt: receivedAt))
        }
        return out
    }

    private func ack(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        guard var req = makeRequest("/relay/ack", method: "POST", auth: true) else { return }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["messageIds": ids])
        _ = try? await session.data(for: req)
    }

    // MARK: - 对外 API

    /// 确认收到（聊天消息展示后立即 ack）
    func acknowledge(messageIds: [String]) {
        let ids = messageIds
        Task { await ack(ids) }
    }

    /// 发送一条消息给指定智能体（deviceId）
    @discardableResult
    func send(toDeviceId: String, payload: [String: Any], ttlHours: Int = 24) async -> Bool {
        guard !token.isEmpty else { return false }
        guard var req = makeRequest("/relay/send", method: "POST", auth: true) else { return false }
        let body: [String: Any] = [
            "to": toDeviceId,
            "type": "agent",
            "ttlHours": ttlHours,
            "payload": payload
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await session.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ok"] as? Bool) == true else { return false }
        return true
    }

    /// 上传文件到文件服务器（multipart），返回可下载 URL。
    /// 约定：服务器返回 `{"ok": true, "url": "https://..."}`。
    func uploadFile(_ data: Data, filename: String, mime: String) async -> String? {
        let base = fileServerURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let url = URL(string: base.hasSuffix("/") ? String(base.dropLast()) : base) else {
            return nil
        }
        let boundary = "AgentPilotBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        guard let (d, _) = try? await session.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let u = obj["url"] as? String, !u.isEmpty else { return nil }
        return u
    }

    /// 拉取中继上的设备列表（用于发现智能体）
    func fetchDevices(selfId: String) async -> [AgentDevice] {
        guard !token.isEmpty else { return [] }
        guard let req = makeRequest("/relay/devices", method: "GET", auth: true) else { return [] }
        guard let (data, _) = try? await session.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let arr = obj["devices"] as? [[String: Any]] else { return [] }
        var out: [AgentDevice] = []
        for d in arr {
            guard let id = d["deviceId"] as? String, id != selfId else { continue }
            out.append(AgentDevice(
                deviceId: id,
                deviceName: (d["deviceName"] as? String) ?? "智能体",
                platform: (d["platform"] as? String) ?? "",
                online: (d["online"] as? Bool) ?? false
            ))
        }
        return out
    }
}
