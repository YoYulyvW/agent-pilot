import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: Store
    @Binding var selection: SidebarSelection?

    private var taskCounts: (active: Int, done: Int) {
        let active = store.tasks.filter { $0.status == .running || $0.status == .blocked }.count
        let done = store.tasks.filter { $0.status == .done }.count
        return (active, done)
    }

    private var totalUnread: Int {
        store.conversations.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("开发任务", systemImage: "checklist")
                    .badge(taskCounts.active)
                    .tag(SidebarSelection.tasks)
                Label("设置", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            } header: {
                Text("工作台")
            }

            Section {
                if store.conversations.isEmpty {
                    Text("暂无智能体会话")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(store.conversations) { conv in
                        ConversationRow(conv: conv)
                            .tag(SidebarSelection.conversation(conv.id))
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteConversation(conv.id)
                                } label: {
                                    Label("删除会话", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("智能体")
                    Spacer()
                    ConnectionBadge(state: store.connectionState)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(store.deviceName.isEmpty ? "智能体控制台" : store.deviceName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if totalUnread > 0 {
                    Text("\(totalUnread)").font(.caption.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .foregroundStyle(.white)
                        .background(Palette.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

private struct ConversationRow: View {
    let conv: Conversation

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(emoji: conv.avatarEmoji, online: conv.isOnline)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conv.title).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    if conv.unreadCount > 0 {
                        Text("\(conv.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Palette.accent)
                            .clipShape(Capsule())
                    } else {
                        Text(conv.updatedAt, style: .time)
                            .font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                }
                Text(conv.lastMessage ?? "开始对话")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
