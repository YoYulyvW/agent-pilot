import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var store: Store

    private var activeTasks: [DevTask] {
        store.tasks.filter { $0.status == .running || $0.status == .blocked || $0.status == .pending }
    }
    private var finishedTasks: [DevTask] {
        store.tasks.filter { $0.status == .done || $0.status == .failed }
    }

    private var overallProgress: Double {
        guard !store.tasks.isEmpty else { return 0 }
        let done = store.tasks.filter { $0.status == .done }.count
        return Double(done) / Double(store.tasks.count)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("总体进度").font(.subheadline).foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text("\(store.tasks.filter { $0.status == .done }.count)/\(store.tasks.count) 已完成")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    ProgressBar(progress: overallProgress, color: Palette.success)
                }
                .padding(.vertical, 6)
            }

            if !activeTasks.isEmpty {
                Section("进行中") {
                    ForEach(activeTasks) { task in
                        TaskRow(task: task)
                    }
                }
            }

            if !finishedTasks.isEmpty {
                Section("已完成 / 失败") {
                    ForEach(finishedTasks) { task in
                        TaskRow(task: task)
                    }
                }
            }

            if store.tasks.isEmpty {
                Section {
                    EmptyStateView(
                        title: "暂无开发任务",
                        systemImage: "checklist",
                        message: "智能体推送任务后会显示在这里。"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("开发任务")
        .refreshable {
            store.reconnect()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
