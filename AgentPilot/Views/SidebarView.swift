import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: Store
    @Binding var selection: SidebarSelection?

    private var activeTaskCount: Int {
        store.tasks.filter { $0.status == .running || $0.status == .blocked }.count
    }
    private var totalUnread: Int {
        store.conversations.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                WorkspaceRow(title: "开发任务", systemImage: "checklist",
                             tint: Palette.accent,
                             badge: activeTaskCount > 0 ? "\(activeTaskCount)" : nil)
                    .tag(SidebarSelection.tasks)
                WorkspaceRow(title: "设置", systemImage: "gearshape",
                             tint: Palette.textSecondary, badge: nil)
                    .tag(SidebarSelection.settings)
            } header: {
                sectionHeader("工作台")
            }

            Section {
                if store.conversations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(Palette.textTertiary)
                        Text("暂无智能体会话")
                            .font(.subheadline).foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(store.conversations) { conv in
                        ConversationRow(conv: conv,
                                        isSelected: selection == .conversation(conv.id))
                            .tag(SidebarSelection.conversation(conv.id))
                            .listRowBackground(
                                selection == .conversation(conv.id)
                                ? Palette.accent.opacity(0.16) : Color.clear
                            )
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
                    sectionHeader("智能体")
                    Spacer()
                    ConnectionBadge(state: store.connectionState)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.bgSurface)
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
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.textTertiary)
            .textCase(nil)
    }
}

// MARK: - 工作台入口行

private struct WorkspaceRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let badge: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Palette.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 会话行

private struct ConversationRow: View {
    let conv: Conversation
    let isSelected: Bool

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
                        .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
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
