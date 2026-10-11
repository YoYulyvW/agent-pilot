import Foundation

enum AppConstants {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let displayName = "智能体控制台"
}

// MARK: - 演示数据（首次启动 / 未配置中继时展示）

enum DemoData {
    static func seed() -> (conversations: [Conversation],
                           messages: [String: [AgentMessage]],
                           tasks: [DevTask]) {
        let now = Date()
        let workbuddyId = "agent-workbuddy"
        let coderId = "agent-coder"

        let c1 = Conversation(id: workbuddyId, title: "WorkBuddy", agentName: "WorkBuddy",
                              avatarEmoji: "🧠", isOnline: true,
                              lastMessage: "开发任务已完成部署，请查收。",
                              updatedAt: now.addingTimeInterval(-120))
        let c2 = Conversation(id: coderId, title: "代码助手", agentName: "CodeAgent",
                              avatarEmoji: "💻", isOnline: false,
                              lastMessage: "重构 PR 已提交，等待 review。",
                              updatedAt: now.addingTimeInterval(-3600))

        let msgs: [String: [AgentMessage]] = [
            workbuddyId: [
                AgentMessage(conversationId: workbuddyId, direction: .incoming, kind: .text,
                             text: "早上好，今天的开发任务清单已经生成。",
                             senderName: "WorkBuddy", timestamp: now.addingTimeInterval(-600)),
                AgentMessage(conversationId: workbuddyId, direction: .incoming, kind: .task,
                             text: "任务「iOS 客户端中继接入」进度 80%",
                             senderName: "WorkBuddy", timestamp: now.addingTimeInterval(-300),
                             taskId: "t-1", taskStatus: "running", progress: 0.8),
                AgentMessage(conversationId: workbuddyId, direction: .outgoing, kind: .text,
                             text: "收到，继续盯着，完成后通知我。",
                             senderName: "我", timestamp: now.addingTimeInterval(-180)),
                AgentMessage(conversationId: workbuddyId, direction: .incoming, kind: .text,
                             text: "开发任务已完成部署，请查收。",
                             senderName: "WorkBuddy", timestamp: now.addingTimeInterval(-120))
            ],
            coderId: [
                AgentMessage(conversationId: coderId, direction: .incoming, kind: .text,
                             text: "侧栏重构完成，等你验收。",
                             senderName: "CodeAgent", timestamp: now.addingTimeInterval(-5400)),
                AgentMessage(conversationId: coderId, direction: .outgoing, kind: .text,
                             text: "好的，稍后看。",
                             senderName: "我", timestamp: now.addingTimeInterval(-4800)),
                AgentMessage(conversationId: coderId, direction: .incoming, kind: .text,
                             text: "重构 PR 已提交，等待 review。",
                             senderName: "CodeAgent", timestamp: now.addingTimeInterval(-3600))
            ]
        ]

        let tasks: [DevTask] = [
            DevTask(id: "t-1", title: "iOS 客户端中继接入", detail: "对接 relay_server.py 长轮询与 ack", status: .running,
                    progress: 0.8, assignedAgent: "WorkBuddy", updatedAt: now.addingTimeInterval(-300)),
            DevTask(id: "t-2", title: "侧栏会话切换", detail: "NavigationSplitView + 会话列表", status: .done,
                    progress: 1.0, assignedAgent: "CodeAgent", updatedAt: now.addingTimeInterval(-3600)),
            DevTask(id: "t-3", title: "GitHub Actions 构建", detail: "无签名 IPA + TrollStore 安装", status: .pending,
                    progress: 0.0, assignedAgent: "WorkBuddy", updatedAt: now.addingTimeInterval(-7200))
        ]

        return (conversations: [c1, c2], messages: msgs, tasks: tasks)
    }
}
