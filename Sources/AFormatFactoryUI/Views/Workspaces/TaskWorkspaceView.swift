import AppKit
import SwiftUI

struct TaskWorkspaceView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var commandPreviewTask: ConversionTask?

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
                        .disabled(viewModel.selectedTaskID == nil || viewModel.isProcessingQueue)

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

                List(selection: $viewModel.selectedTaskID) {
                    ForEach(viewModel.tasks) { task in
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: task.status))
                                .frame(width: 6, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.inputURL.lastPathComponent)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(1)

                                Text("\(task.format.displayName)  ·  \(task.status.displayName)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button("命令") {
                                commandPreviewTask = task
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                Text("任务日志")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                ScrollView {
                    Text(viewModel.selectedTask?.logs ?? "请在左侧选择任务查看日志")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(minHeight: 350)
            }
            .frame(maxWidth: .infinity)
            .cardStyle(padding: 12)
        }
        .sheet(item: $commandPreviewTask) { task in
            commandPreviewSheet(task: task)
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
        }
    }

    private var taskStatsRow: some View {
        HStack(spacing: 8) {
            statsChip(title: "总任务", count: viewModel.tasks.count, icon: "tray.full")
            statsChip(title: "排队", count: count(for: .queued), icon: "clock")
            statsChip(title: "运行", count: count(for: .running), icon: "bolt")
            statsChip(title: "成功", count: count(for: .succeeded), icon: "checkmark.circle")
            statsChip(title: "失败", count: count(for: .failed), icon: "xmark.octagon")
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

    @ViewBuilder
    private func commandPreviewSheet(task: ConversionTask) -> some View {
        let command = viewModel.commandText(for: task)
        VStack(alignment: .leading, spacing: 12) {
            Text("任务命令")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(task.inputURL.lastPathComponent)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(command)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Spacer()
                Button("复制命令") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .buttonStyle(MaterialActionButtonStyle())
            }
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 280)
        .background(.ultraThinMaterial)
    }
}
