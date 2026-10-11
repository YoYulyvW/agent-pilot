import SwiftUI

/// 侧栏选中项
enum SidebarSelection: Hashable {
    case conversation(String)
    case tasks
    case settings
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: SidebarSelection? = .tasks
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
        } detail: {
            switch selection {
            case .conversation(let id):
                ChatView(conversationId: id)
            case .tasks:
                TaskListView()
            case .settings:
                SettingsView()
            case nil:
                EmptyStateView(
                    title: "选择一个会话",
                    systemImage: "bubble.left.and.bubble.right",
                    message: "从左侧选择智能体会话、开发任务或设置。"
                )
            }
        }
        .tint(Palette.accent)
        .background(Palette.bgBase)
        .onChange(of: store.selectedConversationId) { newId in
            if let newId { selection = .conversation(newId) }
        }
    }
}
