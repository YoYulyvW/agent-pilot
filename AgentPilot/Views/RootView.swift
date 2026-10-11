import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var tab: Tab = .conversations
    @State private var convPath = NavigationPath()

    enum Tab: Hashable {
        case conversations, tasks, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $convPath) {
                ConversationListView()
                    .navigationDestination(for: String.self) { id in
                        ChatView(conversationId: id)
                    }
            }
            .tabItem { Label("会话", systemImage: "bubble.left.and.bubble.right") }
            .tag(Tab.conversations)

            NavigationStack {
                TaskListView()
            }
            .tabItem { Label("任务", systemImage: "checklist") }
            .tag(Tab.tasks)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .tint(Palette.accent)
        .onChange(of: store.selectedConversationId) { newId in
            guard let newId, !newId.isEmpty else { return }
            tab = .conversations
            convPath = NavigationPath()
            convPath.append(newId)
        }
    }
}
