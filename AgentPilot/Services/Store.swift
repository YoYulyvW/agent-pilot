import Foundation
import Combine
import SwiftUI
import UIKit

/// 全局状态：会话、消息、任务、中继连接与设置
final class Store: ObservableObject {

    // MARK: - 数据

    @Published var conversations: [Conversation] = []
    @Published var messages: [String: [AgentMessage]] = [:]
    @Published var tasks: [DevTask] = []
    @Published var devices: [AgentDevice] = []

    /// 在线智能体（platform == "agent" 的设备）
    var onlineAgents: [AgentDevice] {
        devices.filter { $0.platform == "agent" }
    }

    // MARK: - 设置

    @Published var relayURL: String {
        didSet { UserDefaults.standard.set(relayURL, forKey: Self.kRelayURL) }
    }
    @Published var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: Self.kDeviceName) }
    }
    @Published var barkKey: String {
        didSet { UserDefaults.standard.set(barkKey, forKey: Self.kBarkKey) }
    }
    @Published var fileServerURL: String {
        didSet { UserDefaults.standard.set(fileServerURL, forKey: Self.kFileServerURL) }
    }

    let transport = RelayTransport()

    @Published var selectedConversationId: String?

    private var selfDeviceId: String
    private let saveQueue = DispatchQueue(label: "com.agentpilot.store", qos: .utility)
    private var savePending = false

    // MARK: - 常量

    private static let kRelayURL = "agentpilot.relayURL"
    private static let kDeviceName = "agentpilot.deviceName"
    private static let kBarkKey = "agentpilot.barkKey"
    private static let kFileServerURL = "agentpilot.fileServerURL"
    private static let kDeviceId = "agentpilot.deviceId"

    private var docsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - 初始化

    init() {
        relayURL = UserDefaults.standard.string(forKey: Self.kRelayURL) ?? ""
        deviceName = UserDefaults.standard.string(forKey: Self.kDeviceName) ?? UIDevice.current.name
        barkKey = UserDefaults.standard.string(forKey: Self.kBarkKey) ?? ""
        fileServerURL = UserDefaults.standard.string(forKey: Self.kFileServerURL) ?? ""

        if let saved = UserDefaults.standard.string(forKey: Self.kDeviceId), !saved.isEmpty {
            selfDeviceId = saved
        } else {
            selfDeviceId = UUID().uuidString
            UserDefaults.standard.set(selfDeviceId, forKey: Self.kDeviceId)
        }

        load()
        if conversations.isEmpty {
            seedDemo()
        }

        transport.onIncoming = { [weak self] env in
            self?.handleIncoming(env)
        }
        transport.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        applyTransport()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 中继启停

    func applyTransport() {
        transport.fileServerURL = fileServerURL
        if relayURL.trimmingCharacters(in: .whitespaces).isEmpty {
            transport.stop()
        } else {
            transport.start(url: relayURL, devId: selfDeviceId, devName: deviceName, barkKey: barkKey)
        }
    }

    var connectionState: RelayTransport.State { transport.state }

    func reconnect() {
        transport.stop()
        applyTransport()
    }

    // MARK: - 入站处理

    private func handleIncoming(_ env: IncomingEnvelope) {
        guard env.type == "agent" else { return }
        let p = env.payload
        let kindRaw = (p["kind"] as? String) ?? "text"
        var kind = MessageKind(rawValue: kindRaw) ?? .text
        let text = (p["text"] as? String) ?? ""
        let agentId = (p["agentId"] as? String) ?? env.from
        let agentName = (p["agentName"] as? String) ?? env.fromName
        let ts = (p["ts"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? env.receivedAt
        let bizId = (p["messageId"] as? String) ?? (p["bizId"] as? String)
        let toolName = p["toolName"] as? String
        let toolState = p["toolState"] as? String

        // 解码附件
        var attachments: [Attachment] = []
        if let arr = p["attachments"] as? [[String: Any]] {
            attachments = arr.compactMap { Attachment.from(wire: $0) }
        }
        if kind == .text && !attachments.isEmpty && text.isEmpty {
            kind = .attachment
        }

        // edit 逻辑：相同 bizId 原地更新原消息（工具进度等，不刷屏）
        if let bizId, !bizId.isEmpty,
           let idx = messages[agentId]?.firstIndex(where: { $0.bizId == bizId }) {
            var arr = messages[agentId] ?? []
            arr[idx].kind = kind
            if !text.isEmpty { arr[idx].text = text }
            arr[idx].toolName = toolName ?? arr[idx].toolName
            arr[idx].toolState = toolState ?? arr[idx].toolState
            if !attachments.isEmpty { arr[idx].attachments = attachments }
            arr[idx].timestamp = ts
            messages[agentId] = arr

            let updated = arr[idx]
            if let cidx = conversations.firstIndex(where: { $0.id == agentId }) {
                conversations[cidx].lastMessage = Self.previewText(for: updated)
                conversations[cidx].updatedAt = ts
            }
            transport.acknowledge(messageIds: [env.messageId])
            scheduleSave()
            return
        }

        let msg = AgentMessage(
            id: env.messageId,
            conversationId: agentId,
            direction: .incoming,
            kind: kind,
            text: text,
            senderName: agentName,
            timestamp: ts,
            attachments: attachments,
            bizId: bizId,
            toolName: toolName,
            toolState: toolState,
            taskId: p["taskId"] as? String,
            taskStatus: p["taskStatus"] as? String,
            progress: p["progress"] as? Double
        )

        upsertConversation(for: agentId, agentName: agentName, message: msg)
        appendMessage(msg)

        // 任务类消息 → 同步开发任务
        switch kind {
        case .task:
            upsertTask(from: p, agentName: agentName)
        case .taskList:
            if let list = p["tasks"] as? [[String: Any]] {
                for item in list { upsertTask(from: item, agentName: agentName) }
            }
        default:
            break
        }

        // 聊天消息展示后立即 ack
        transport.acknowledge(messageIds: [env.messageId])
        scheduleSave()
    }

    static func previewText(for m: AgentMessage) -> String {
        if m.kind == .tool {
            let name = m.toolName ?? "工具"
            let mark: String
            switch m.toolState {
            case "done": mark = "✅"
            case "failed": mark = "❌"
            default: mark = "🔧"
            }
            return "\(mark) \(name)"
        }
        if !m.text.isEmpty { return m.text }
        if !m.attachments.isEmpty {
            let hasImage = m.attachments.contains { $0.kind == .image }
            let hasFile = m.attachments.contains { $0.kind == .file }
            if hasImage && hasFile { return "[图片 + 文件]" }
            return hasImage ? "[图片]" : "[文件]"
        }
        return m.text
    }

    private func upsertConversation(for id: String, agentName: String, message: AgentMessage) {
        let online = (message.kind == .status) ? (message.taskStatus != "offline") : true
        let preview = Self.previewText(for: message)
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].agentName = agentName
            conversations[idx].isOnline = online
            conversations[idx].lastMessage = preview
            conversations[idx].updatedAt = message.timestamp
            if conversations[idx].id != selectedConversationId {
                conversations[idx].unreadCount += 1
            }
        } else {
            let c = Conversation(id: id, title: agentName, agentName: agentName,
                                 avatarEmoji: "🤖", isOnline: online,
                                 lastMessage: preview, updatedAt: message.timestamp,
                                 unreadCount: id == selectedConversationId ? 0 : 1)
            conversations.insert(c, at: 0)
        }
        sortConversations()
    }

    private func sortConversations() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func appendMessage(_ m: AgentMessage) {
        messages[m.conversationId, default: []].append(m)
    }

    private func appendSystemMessage(_ convId: String, text: String) {
        let m = AgentMessage(conversationId: convId, direction: .incoming,
                             kind: .system, text: text, senderName: "系统")
        appendMessage(m)
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].lastMessage = text
            conversations[idx].updatedAt = Date()
        }
        scheduleSave()
    }

    private func upsertTask(from p: [String: Any], agentName: String) {
        guard let id = p["taskId"] as? String, !id.isEmpty else { return }
        let title = (p["taskTitle"] as? String) ?? (p["title"] as? String) ?? "未命名任务"
        let detail = (p["taskDetail"] as? String) ?? (p["detail"] as? String) ?? ""
        let status = TaskStatus(rawValue: (p["taskStatus"] as? String) ?? (p["status"] as? String) ?? "pending") ?? .pending
        let progress = (p["progress"] as? Double) ?? (status == .done ? 1.0 : 0.0)
        let ts = (p["ts"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()

        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].title = title
            tasks[idx].detail = detail
            tasks[idx].status = status
            tasks[idx].progress = min(max(progress, 0), 1)
            tasks[idx].assignedAgent = agentName.isEmpty ? tasks[idx].assignedAgent : agentName
            tasks[idx].updatedAt = ts
        } else {
            tasks.append(DevTask(id: id, title: title, detail: detail, status: status,
                                 progress: progress, assignedAgent: agentName, updatedAt: ts))
        }
        sortTasks()
    }

    private func sortTasks() {
        let order: [TaskStatus] = [.running, .blocked, .pending, .failed, .done]
        tasks.sort { a, b in
            let ia = order.firstIndex(of: a.status) ?? 99
            let ib = order.firstIndex(of: b.status) ?? 99
            if ia != ib { return ia < ib }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: - 发送

    /// 发送文本 + 图片 + 文件
    @discardableResult
    func sendMessage(to convId: String, text: String, images: [UIImage], files: [OutgoingFile]) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty || !files.isEmpty else { return false }

        var attachments: [Attachment] = []
        var tooLarge = 0

        for img in images {
            let data = AttachmentHelper.compressImage(img)
            attachments.append(Attachment(kind: .image, name: "image.jpg",
                                          mimeType: "image/jpeg", sizeBytes: data.count,
                                          dataBase64: data.base64EncodedString()))
        }

        for f in files {
            if f.data.count <= AttachmentHelper.maxInlineDataBytes {
                attachments.append(Attachment(kind: .file, name: f.name, mimeType: f.mimeType,
                                              sizeBytes: f.data.count,
                                              dataBase64: f.data.base64EncodedString()))
            } else if transport.isConnected, !transport.fileServerURL.isEmpty {
                if let url = await transport.uploadFile(f.data, filename: f.name, mime: f.mimeType) {
                    attachments.append(Attachment(kind: .file, name: f.name, mimeType: f.mimeType,
                                                  sizeBytes: f.data.count, url: url))
                } else {
                    tooLarge += 1
                }
            } else {
                tooLarge += 1
            }
        }

        if tooLarge > 0 {
            appendSystemMessage(convId, text: "⚠️ \(tooLarge) 个文件过大未发送（内联上限 \(AttachmentHelper.readableSize(AttachmentHelper.maxInlineDataBytes))，大文件请在设置里配置文件服务器）")
        }

        guard !attachments.isEmpty || !trimmed.isEmpty else { return false }

        let kind: MessageKind = trimmed.isEmpty ? .attachment : .text
        let msg = AgentMessage(conversationId: convId, direction: .outgoing, kind: kind,
                               text: trimmed, senderName: "我", attachments: attachments)
        appendMessage(msg)
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].lastMessage = Self.previewText(for: msg)
            conversations[idx].updatedAt = Date()
        }
        sortConversations()
        scheduleSave()

        // 发送前确保连接：断了就重连再试
        if !transport.isConnected {
            applyTransport()
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        if transport.isConnected {
            var payload: [String: Any] = [
                "v": 1,
                "kind": kind.rawValue,
                "text": trimmed,
                "senderId": selfDeviceId,
                "senderName": deviceName,
                "ts": Date().timeIntervalSince1970
            ]
            if !attachments.isEmpty {
                payload["attachments"] = attachments.map { $0.wireDict }
            }
            let ok = await transport.send(toDeviceId: convId, payload: payload)
            if !ok {
                appendSystemMessage(convId, text: "⚠️ 消息发送失败：中继未响应")
            }
            return ok
        }
        appendSystemMessage(convId, text: "⚠️ 消息未发出：中继未连接，请到「设置」检查地址")
        return false
    }

    /// 向某个智能体下达一条任务指令
    @discardableResult
    func sendTaskCommand(to agentId: String, title: String) async -> Bool {
        guard transport.isConnected else { return false }
        let payload: [String: Any] = [
            "v": 1,
            "kind": "task",
            "text": title,
            "taskId": UUID().uuidString,
            "taskTitle": title,
            "taskStatus": "pending",
            "progress": 0.0,
            "senderId": selfDeviceId,
            "senderName": deviceName,
            "ts": Date().timeIntervalSince1970
        ]
        return await transport.send(toDeviceId: agentId, payload: payload)
    }

    // MARK: - 设备发现

    func refreshDevices() async {
        let list = await transport.fetchDevices(selfId: selfDeviceId)
        await MainActor.run { self.devices = list }
    }

    /// 从设备列表主动发起与某个智能体的会话
    func startConversation(deviceId: String, name: String) {
        if conversations.firstIndex(where: { $0.id == deviceId }) == nil {
            let c = Conversation(id: deviceId, title: name, agentName: name,
                                 avatarEmoji: "🤖", isOnline: true)
            conversations.insert(c, at: 0)
            scheduleSave()
        }
        selectedConversationId = deviceId
    }

    // MARK: - 会话交互

    func markRead(_ convId: String) {
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].unreadCount = 0
        }
    }

    func deleteConversation(_ convId: String) {
        conversations.removeAll { $0.id == convId }
        messages.removeValue(forKey: convId)
        if selectedConversationId == convId { selectedConversationId = nil }
        scheduleSave()
    }

    func messages(for convId: String) -> [AgentMessage] {
        messages[convId] ?? []
    }

    // MARK: - 演示数据

    private func seedDemo() {
        let demo = DemoData.seed()
        conversations = demo.conversations
        messages = demo.messages
        tasks = demo.tasks
        scheduleSave()
    }

    // MARK: - 持久化

    private struct Snapshot: Codable {
        var conversations: [Conversation]
        var messages: [String: [AgentMessage]]
        var tasks: [DevTask]
    }

    private func load() {
        let url = docsDir.appendingPathComponent("agentpilot.json")
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        conversations = snap.conversations
        messages = snap.messages
        tasks = snap.tasks
    }

    func scheduleSave() {
        saveQueue.async { [weak self] in
            guard let self else { return }
            if self.savePending { return }
            self.savePending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.savePending = false
                self.saveNow()
            }
        }
    }

    private func saveNow() {
        let snap = Snapshot(conversations: conversations, messages: messages, tasks: tasks)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: docsDir.appendingPathComponent("agentpilot.json"), options: .atomic)
    }
}
