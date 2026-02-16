import SwiftUI

struct TaskWorkspaceView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                taskStatsRow

                HStack {
                    Text("任务队列")
                        .font(.system(size: 15, weight: .bold, design: .rounded))

                    Spacer()

                    Button(viewModel.isProcessingQueue ? "执行中..." : "开始队列") {
                        Task { await viewModel.startQueuedTasks() }
                    }
                    .buttonStyle(MaterialActionButtonStyle())
                    .disabled(viewModel.isProcessingQueue)

                    Button("清理已完成") { viewModel.clearFinishedTasks() }
                        .buttonStyle(MaterialActionButtonStyle())

                    Button("删除任务") { viewModel.removeSelectedTask() }
                        .buttonStyle(MaterialActionButtonStyle())
                        .disabled(viewModel.selectedTaskIDs.isEmpty || viewModel.isProcessingQueue)

                    Button("终止任务") { viewModel.terminateSelectedTask() }
                        .buttonStyle(MaterialActionButtonStyle())
                        .disabled(!viewModel.canTerminateSelectedTask)

                    Stepper(value: $viewModel.maxConcurrentTasks, in: 1...viewModel.maxConcurrentTaskLimit) {
                        Text("并发 \(viewModel.maxConcurrentTasks)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(width: 110)
                }

                Text("提示：可在列表中直接拖拽任务行调整顺序。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                List(selection: $viewModel.selectedTaskIDs) {
                    ForEach(viewModel.tasks) { task in
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: task.status))
                                .frame(width: 6, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.inputURL.lastPathComponent)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(1)

                                Text(subtitle(for: task))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(1)

                                if task.status == .running {
                                    ProgressView(value: task.progress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 180)
                                }
                            }

                            Spacer(minLength: 8)
                        }
                        .tag(task.id)
                    }
                    .onDelete(perform: viewModel.removeTasks)
                    .onMove(perform: viewModel.moveTasks)
                }
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(minHeight: 350)
            }
            .frame(maxWidth: .infinity)
            .cardStyle(padding: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("任务详情")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Group {
                    if let task = viewModel.selectedTask {
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow("状态", subtitle(for: task))
                            detailRow("输入", task.inputURL.path)
                            detailRow("输出", task.outputURL.path)
                            detailRow("参数", task.optionsSummary)
                            if let startedAt = task.startedAt {
                                detailRow("开始", startedAt.formatted(date: .omitted, time: .standard))
                            }
                            if let finishedAt = task.finishedAt {
                                detailRow("结束", finishedAt.formatted(date: .omitted, time: .standard))
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text("错误日志")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.top, 4)

                        ScrollView {
                            Text(task.logs.isEmpty ? "暂无错误日志" : task.logs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                        }
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ScrollView {
                            Text("请在左侧选择任务查看详情")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .padding(10)
                        }
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(minHeight: 350)
            }
            .frame(maxWidth: .infinity)
            .cardStyle(padding: 12)
        }
    }

    private func color(for status: ConversionTaskStatus) -> Color {
        switch status {
        case .queued:
            return .gray
        case .running:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .yellow
        }
    }

    private var taskStatsRow: some View {
        HStack(spacing: 8) {
            statsChip(title: "总任务", count: viewModel.tasks.count, icon: "tray.full")
            statsChip(title: "排队", count: count(for: .queued), icon: "clock")
            statsChip(title: "运行", count: count(for: .running), icon: "bolt")
            statsChip(title: "成功", count: count(for: .succeeded), icon: "checkmark.circle")
            statsChip(title: "失败", count: count(for: .failed), icon: "xmark.octagon")
            statsChip(title: "终止", count: count(for: .cancelled), icon: "stop.circle")
            Spacer()
        }
    }

    private func statsChip(title: String, count: Int, icon: String) -> some View {
        Label("\(title) \(count)", systemImage: icon)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }

    private func count(for status: ConversionTaskStatus) -> Int {
        viewModel.tasks.filter { $0.status == status }.count
    }

    private func subtitle(for task: ConversionTask) -> String {
        if task.status == .running {
            let ratioText = "\(Int(task.progress * 100))%"
            let timeText = task.processedTimeSeconds.map { formatDuration(seconds: $0) } ?? "--:--"
            let speedText = task.speed.map { String(format: "%.2fx", $0) } ?? "--x"
            let bitrateText = task.bitrateKbps.map { String(format: "%.0f kb/s", $0) } ?? "-- kb/s"
            let frameText = task.processedFrames.map { "帧 \(Int($0))" } ?? "帧 --"
            return "\(task.format.displayName)  ·  \(ratioText)  ·  \(timeText)  ·  \(speedText)  ·  \(bitrateText)  ·  \(frameText)"
        }
        return "\(task.format.displayName)  ·  \(task.status.displayName)"
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatDuration(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
