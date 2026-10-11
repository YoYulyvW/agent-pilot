import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var store: Store

    private var totalUnread: Int {
        store.conversations.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        List {
            // 在线智能体（可主动选择对话）
            Section {
                if store.onlineAgents.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Palette.textTertiary)
                        Text(store.connectionState == .connected ? "暂无在线智能体" : "未连接中继，请先到「设置」填写中继地址")
                            .font(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(store.onlineAgents) { agent in
                        Button {
                            store.startConversation(deviceId: agent.deviceId, name: agent.deviceName)
                        } label: {
                            AgentRow(agent: agent)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Palette.bgSurface)
                    }
                }
            } header: {
                HStack {
                    Text("在线智能体")
                    Spacer()
                    if !store.onlineAgents.isEmpty {
                        Text("\(store.onlineAgents.count) 个")
                    }
                }
                .textCase(nil)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
            } footer: {
                Text("智能体（WorkBuddy / Codex 等）接入中继后出现在这里，点选即可对话。")
            }

            // 会话历史
            Section {
                if store.conversations.isEmpty {
                    EmptyStateView(
                        title: "还没有会话",
                        systemImage: "bubble.left.and.bubble.right",
                        message: "从上方选择一个在线智能体开始对话，\n或等智能体主动给你发消息。"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.conversations) { conv in
                        NavigationLink(value: conv.id) {
                            ConversationRow(conv: conv)
                        }
                        .listRowBackground(Palette.bgSurface)
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
                    Text("会话")
                    Spacer()
                    ConnectionBadge(state: store.connectionState)
                }
                .textCase(nil)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.bgBase)
        .navigationTitle("智能体控制台")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Palette.accent)
                            .frame(width: 28, height: 28)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("智能体控制台")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if totalUnread > 0 {
                    Text("\(totalUnread)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Palette.accent)
                        .clipShape(Capsule())
                }
            }
        }
        .onAppear {
            Task { await store.refreshDevices() }
        }
        .refreshable {
            store.reconnect()
            await store.refreshDevices()
        }
    }
}

// MARK: - 在线智能体行

private struct AgentRow: View {
    let agent: AgentDevice

    var body: some View {
        HStack(spacing: 10) {
            Text("🤖")
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(Palette.bgElevated)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.deviceName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(agent.online ? "在线 · 点击对话" : "离线")
                    .font(.caption2)
                    .foregroundStyle(agent.online ? Palette.success : Palette.textTertiary)
            }
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(Palette.accent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 会话行

private struct ConversationRow: View {
    let conv: Conversation

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(emoji: conv.avatarEmoji, online: conv.isOnline)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conv.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(conv.updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                }
                HStack(spacing: 6) {
                    Text(conv.lastMessage ?? "开始对话")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if conv.unreadCount > 0 {
                        Text("\(conv.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}
