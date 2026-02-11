import SwiftUI

struct TaskWorkspaceView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
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

                    Stepper(value: $viewModel.maxConcurrentTasks, in: 1...8) {
                        Text("并发 \(viewModel.maxConcurrentTasks)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(width: 110)
                }

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
                        }
                        .tag(task.id)
                    }
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
}
