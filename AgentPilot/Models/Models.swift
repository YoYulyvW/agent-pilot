import Foundation

// MARK: - 附件

struct Attachment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case image
        case file
    }

    var id: String
    var kind: Kind
    var name: String
    var mimeType: String
    var sizeBytes: Int
    var dataBase64: String?   // 内联（小文件/图片，走中继转发）
    var url: String?          // 远程（大文件走文件服务器）

    init(id: String = UUID().uuidString,
         kind: Kind,
         name: String,
         mimeType: String = "application/octet-stream",
         sizeBytes: Int = 0,
         dataBase64: String? = nil,
         url: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.dataBase64 = dataBase64
        self.url = url
    }

    var data: Data? {
        guard let s = dataBase64 else { return nil }
        return Data(base64Encoded: s)
    }

    var isRemote: Bool { url != nil }

    // 中继 wire 格式
    var wireDict: [String: Any] {
        var d: [String: Any] = [
            "id": id, "kind": kind.rawValue, "name": name,
            "mime": mimeType, "size": sizeBytes
        ]
        if let dataBase64 { d["data"] = dataBase64 }
        if let url { d["url"] = url }
        return d
    }

    static func from(wire: [String: Any]) -> Attachment? {
        let kind = (wire["kind"] as? String) == "image" ? Kind.image : Kind.file
        return Attachment(
            id: (wire["id"] as? String) ?? UUID().uuidString,
            kind: kind,
            name: (wire["name"] as? String) ?? "附件",
            mimeType: (wire["mime"] as? String) ?? "application/octet-stream",
            sizeBytes: (wire["size"] as? Int) ?? 0,
            dataBase64: wire["data"] as? String,
            url: wire["url"] as? String
        )
    }
}

// MARK: - 消息

/// 消息方向
enum MessageDirection: String, Codable {
    case incoming   // 智能体 → 手机
    case outgoing   // 手机 → 智能体
}

/// 消息类型
enum MessageKind: String, Codable {
    case text        // 普通文本
    case attachment  // 图片/文件
    case tool        // 工具调用进度（running/done/failed）
    case task        // 单条任务状态更新
    case taskList    // 任务清单同步
    case status      // 系统/连接状态
    case system      // 提示类
}

struct AgentMessage: Identifiable, Codable, Equatable {
    var id: String
    var conversationId: String
    var direction: MessageDirection
    var kind: MessageKind
    var text: String
    var senderName: String
    var timestamp: Date
    var attachments: [Attachment]
    // 业务 id（agent 侧生成的稳定 id）：相同 bizId = 更新（edit）原消息
    var bizId: String?
    // 工具调用（kind == .tool 时使用）
    var toolName: String?
    var toolState: String?   // running / done / failed
    // 任务相关（kind == .task 时使用）
    var taskId: String?
    var taskStatus: String?
    var progress: Double?

    init(id: String = UUID().uuidString,
         conversationId: String,
         direction: MessageDirection,
         kind: MessageKind = .text,
         text: String,
         senderName: String = "",
         timestamp: Date = Date(),
         attachments: [Attachment] = [],
         bizId: String? = nil,
         toolName: String? = nil,
         toolState: String? = nil,
         taskId: String? = nil,
         taskStatus: String? = nil,
         progress: Double? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.direction = direction
        self.kind = kind
        self.text = text
        self.senderName = senderName
        self.timestamp = timestamp
        self.attachments = attachments
        self.bizId = bizId
        self.toolName = toolName
        self.toolState = toolState
        self.taskId = taskId
        self.taskStatus = taskStatus
        self.progress = progress
    }

    // 兼容旧存档：新增字段缺失时回退默认
    enum CodingKeys: String, CodingKey {
        case id, conversationId, direction, kind, text, senderName, timestamp
        case attachments, bizId, toolName, toolState, taskId, taskStatus, progress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        direction = try c.decode(MessageDirection.self, forKey: .direction)
        kind = try c.decode(MessageKind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        bizId = try c.decodeIfPresent(String.self, forKey: .bizId)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        toolState = try c.decodeIfPresent(String.self, forKey: .toolState)
        taskId = try c.decodeIfPresent(String.self, forKey: .taskId)
        taskStatus = try c.decodeIfPresent(String.self, forKey: .taskStatus)
        progress = try c.decodeIfPresent(Double.self, forKey: .progress)
    }
}

// MARK: - 会话

struct Conversation: Identifiable, Codable, Equatable {
    var id: String            // = 智能体在中继上的 deviceId
    var title: String
    var agentName: String
    var avatarEmoji: String
    var isOnline: Bool
    var lastMessage: String?
    var updatedAt: Date
    var unreadCount: Int

    init(id: String,
         title: String,
         agentName: String,
         avatarEmoji: String = "🤖",
         isOnline: Bool = false,
         lastMessage: String? = nil,
         updatedAt: Date = Date(),
         unreadCount: Int = 0) {
        self.id = id
        self.title = title
        self.agentName = agentName
        self.avatarEmoji = avatarEmoji
        self.isOnline = isOnline
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
        self.unreadCount = unreadCount
    }
}

// MARK: - 开发任务

enum TaskStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case running = "running"
    case blocked = "blocked"
    case done = "done"
    case failed = "failed"

    var display: String {
        switch self {
        case .pending: return "待开始"
        case .running: return "进行中"
        case .blocked: return "受阻"
        case .done: return "已完成"
        case .failed: return "失败"
        }
    }

    var colorName: String {
        switch self {
        case .pending: return "gray"
        case .running: return "blue"
        case .blocked: return "orange"
        case .done: return "green"
        case .failed: return "red"
        }
    }
}

struct DevTask: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var detail: String
    var status: TaskStatus
    var progress: Double        // 0.0 ... 1.0
    var assignedAgent: String   // 负责的智能体名
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         title: String,
         detail: String = "",
         status: TaskStatus = .pending,
         progress: Double = 0,
         assignedAgent: String = "",
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.progress = min(max(progress, 0), 1)
        self.assignedAgent = assignedAgent
        self.updatedAt = updatedAt
    }
}

// MARK: - 中继设备（智能体）

struct AgentDevice: Identifiable, Codable {
    var deviceId: String
    var deviceName: String
    var platform: String
    var online: Bool
    var id: String { deviceId }
}
