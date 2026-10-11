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
                summaryCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if !activeTasks.isEmpty {
                Section {
                    ForEach(activeTasks) { task in
                        TaskRow(task: task)
                            .listRowBackground(Palette.bgSurface)
                    }
                } header: {
                    sectionHeader("进行中")
                }
            }

            if !finishedTasks.isEmpty {
                Section {
                    ForEach(finishedTasks) { task in
                        TaskRow(task: task)
                            .listRowBackground(Palette.bgSurface)
                    }
                } header: {
                    sectionHeader("已完成 / 失败")
                }
            }

            if store.tasks.isEmpty {
                Section {
                    EmptyStateView(
                        title: "暂无开发任务",
                        systemImage: "checklist",
                        message: "智能体推送任务后会显示在这里。"
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.bgBase)
        .navigationTitle("开发任务")
        .refreshable {
            store.reconnect()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("开发进度")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(overallProgress * 100))%")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            ProgressBar(progress: overallProgress, color: .white)
            HStack {
                statItem("进行中", activeTasks.filter { $0.status == .running }.count, .white)
                statItem("受阻", activeTasks.filter { $0.status == .blocked }.count, .white)
                statItem("已完成", store.tasks.filter { $0.status == .done }.count, .white)
                statItem("总计", store.tasks.count, .white)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Palette.accent, Palette.accentGradient2],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 2).padding(.top, 2)
    }

    private func statItem(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.headline)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
    }
}
