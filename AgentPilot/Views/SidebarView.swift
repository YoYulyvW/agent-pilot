import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var store: Store

    private var totalUnread: Int {
        store.conversations.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        List {
            Section {
                if store.conversations.isEmpty {
                    EmptyStateView(
                        title: "暂无智能体会话",
                        systemImage: "bubble.left.and.bubble.right",
                        message: "智能体发来消息后会自动出现在这里，\n也可到「设置 → 在线智能体」主动发起对话。"
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
                    Text("智能体")
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
        .refreshable {
            store.reconnect()
        }
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
