import SwiftUI

struct WorkspaceSidebarView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Binding var selectedSection: WorkspaceSection?

    var body: some View {
        List(selection: $selectedSection) {
            Section("格式转换") {
                Label(WorkspaceSection.videoConvert.title, systemImage: WorkspaceSection.videoConvert.symbol)
                    .tag(WorkspaceSection.videoConvert)
                Label(WorkspaceSection.audioConvert.title, systemImage: WorkspaceSection.audioConvert.symbol)
                    .tag(WorkspaceSection.audioConvert)
            }

            Section("工作区") {
                Label(WorkspaceSection.tasks.title, systemImage: WorkspaceSection.tasks.symbol)
                    .tag(WorkspaceSection.tasks)
                Label(WorkspaceSection.appLog.title, systemImage: WorkspaceSection.appLog.symbol)
                    .tag(WorkspaceSection.appLog)
            }

            Section("状态") {
                Label("总任务 \(viewModel.tasks.count)", systemImage: "tray.full")
                Label("排队 \(count(for: .queued))", systemImage: "clock")
                Label("运行 \(count(for: .running))", systemImage: "bolt")
                Label("成功 \(count(for: .succeeded))", systemImage: "checkmark.circle")
                Label("失败 \(count(for: .failed))", systemImage: "xmark.octagon")
            }
        }
        .navigationTitle("AFormatFactory")
        .listStyle(.sidebar)
    }

    private func count(for status: ConversionTaskStatus) -> Int {
        viewModel.tasks.filter { $0.status == status }.count
    }
}
