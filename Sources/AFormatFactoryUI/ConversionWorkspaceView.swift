import SwiftUI

struct ConversionWorkspaceView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Binding var selectedSection: WorkspaceSection?
    let targetDomain: ConversionDomain

    var body: some View {
        VStack(spacing: 12) {
            controlCard
            addTaskBar
        }
        .onAppear { viewModel.domain = targetDomain }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.domain == .video ? "视频格式转换" : "音频格式转换")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Button("选择输入文件") { viewModel.pickInputFiles() }
                    .buttonStyle(MaterialActionButtonStyle())

                Picker("输出格式", selection: $viewModel.format) {
                    ForEach(viewModel.availableFormats) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Spacer()
            }

            HStack(spacing: 10) {
                Text("输出位置")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                Picker("输出位置", selection: $viewModel.outputLocationMode) {
                    ForEach(OutputLocationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)

                if viewModel.outputLocationMode == .specifiedDirectory {
                    Button("选择输出目录") { viewModel.pickOutputDirectory() }
                        .buttonStyle(MaterialActionButtonStyle())
                }

                Spacer()
            }

            outputDirectoryHint

            Divider().overlay(.white.opacity(0.2))

            selectedFilesPanel

            Divider().overlay(.white.opacity(0.2))

            ParameterEditorView(viewModel: viewModel)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var outputDirectoryHint: some View {
        if viewModel.outputLocationMode == .sourceDirectory {
            Text("输出目录：源文件所在目录（每个任务按各自源文件目录输出）")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        } else if let output = viewModel.outputDirectory {
            Text("输出目录：\(output.path)")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        } else {
            Text("输出目录：未选择")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var selectedFilesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已选输入文件（\(viewModel.selectedFiles.count)）")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if viewModel.selectedFiles.isEmpty {
                Text("尚未选择输入文件")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.selectedFiles, id: \.self) { file in
                            HStack(spacing: 8) {
                                Text(file.path)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)

                                Button {
                                    viewModel.removeSelectedInputFile(file)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                .buttonStyle(.plain)
                                .help("从已选输入文件中删除")
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 80, maxHeight: 150)
                .background(Color.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var addTaskBar: some View {
        HStack {
            Spacer()
            Button("添加任务") {
                let added = viewModel.addTasksFromSelection()
                if added > 0 {
                    selectedSection = .tasks
                }
            }
            .buttonStyle(MaterialActionButtonStyle())
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}
