import SwiftUI

@main
struct AgentPilotApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)   // 对齐 WorkBuddy 深色主题
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // 回到前台立即拉一次中继上的新消息
                store.reconnect()
            }
        }
    }
}
