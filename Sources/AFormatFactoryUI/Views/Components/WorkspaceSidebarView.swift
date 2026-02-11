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
        }
        .navigationTitle("AFormatFactory")
        .listStyle(.sidebar)
    }
}
