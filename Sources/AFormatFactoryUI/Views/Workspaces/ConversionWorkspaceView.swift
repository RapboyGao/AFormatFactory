import SwiftUI

struct ConversionWorkspaceView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Binding var selectedSection: WorkspaceSection?
    let targetDomain: ConversionDomain

    @StateObject private var previewSession = PreviewSessionStore()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            previewColumn
            controlColumn
        }
        .onAppear {
            viewModel.domain = targetDomain
            viewModel.refreshPreviewTargetIfNeeded()
            viewModel.applyParametersToPreview()
        }
        .onChange(of: viewModel.previewCropRect) { _, _ in viewModel.syncPreviewToParameters() }
        .onChange(of: viewModel.previewTransformState) { _, _ in viewModel.syncPreviewToParameters() }
        .onChange(of: viewModel.previewTimeRangeStart) { _, _ in viewModel.syncPreviewToParameters() }
        .onChange(of: viewModel.previewTimeRangeEnd) { _, _ in viewModel.syncPreviewToParameters() }
        .onChange(of: viewModel.videoRotate) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.videoFlipHorizontal) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.videoFlipVertical) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.videoCropWidth) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.videoCropHeight) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.videoCropX) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.videoCropY) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.startTime) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: viewModel.duration) { _, _ in viewModel.applyParametersToPreview() }
        .onChange(of: previewSession.naturalVideoSize) { _, size in
            viewModel.previewVideoSize = size
            viewModel.applyParametersToPreview()
        }
        .onChange(of: previewSession.durationSeconds) { _, duration in
            viewModel.previewDurationSeconds = duration
            if viewModel.previewTimeRangeEnd == nil && duration > 0 {
                viewModel.previewTimeRangeEnd = duration
            }
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("预览编辑")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Picker("编辑模式", selection: $viewModel.editorMode) {
                    ForEach(PreviewEditorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                Button(viewModel.isPreviewPlaying ? "暂停" : "播放") {
                    viewModel.isPreviewPlaying.toggle()
                }
                .buttonStyle(MaterialActionButtonStyle())

                Button("导出当前帧") { viewModel.exportCurrentFrame() }
                    .buttonStyle(MaterialActionButtonStyle())
                    .disabled(viewModel.domain != .video || viewModel.previewTargetFile == nil)

                Button("撤销") { viewModel.undoPreviewEdit() }
                    .buttonStyle(MaterialActionButtonStyle())
                Button("重做") { viewModel.redoPreviewEdit() }
                    .buttonStyle(MaterialActionButtonStyle())
            }

            HStack(spacing: 8) {
                Text("裁剪比例")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                ForEach(PreviewAspectPreset.allCases) { preset in
                    Button(preset.displayName) {
                        viewModel.previewAspectPreset = preset
                    }
                    .buttonStyle(MaterialActionButtonStyle())
                }
                Button("重置裁剪") {
                    viewModel.pushPreviewSnapshot()
                    viewModel.previewCropRect = .full
                }
                .buttonStyle(MaterialActionButtonStyle())

                Spacer()
            }

            if viewModel.domain == .video {
                PreviewPlayerView(
                    session: previewSession,
                    url: viewModel.previewTargetFile,
                    cropRect: $viewModel.previewCropRect,
                    aspectPreset: $viewModel.previewAspectPreset,
                    transform: $viewModel.previewTransformState,
                    playhead: $viewModel.previewPlayheadSeconds,
                    isPlaying: $viewModel.isPreviewPlaying,
                    showCropOverlay: viewModel.editorMode == .crop
                )
            } else {
                AudioPreviewView(url: viewModel.previewTargetFile, isPlaying: $viewModel.isPreviewPlaying, playhead: $viewModel.previewPlayheadSeconds)
            }

            TimelineStripView(
                totalDuration: previewSession.durationSeconds,
                start: $viewModel.previewTimeRangeStart,
                end: $viewModel.previewTimeRangeEnd,
                playhead: $viewModel.previewPlayheadSeconds
            )

            filterGraphEditor
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var filterGraphEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("滤镜链")
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Button("+视频滤镜") {
                    viewModel.addFilterNode(FilterNode(kind: .eq))
                }
                .buttonStyle(MaterialActionButtonStyle())

                Button("+音频滤镜") {
                    viewModel.addFilterNode(FilterNode(kind: .highpass))
                }
                .buttonStyle(MaterialActionButtonStyle())

                Spacer()

                Text("最终 -vf/-af 会与任务命令一致")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if viewModel.filterGraph.videoNodes.isEmpty && viewModel.filterGraph.audioNodes.isEmpty {
                Text("暂无自定义滤镜节点")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.filterGraph.videoNodes) { node in
                            filterNodeRow(node: node, isVideo: true)
                        }
                        ForEach(viewModel.filterGraph.audioNodes) { node in
                            filterNodeRow(node: node, isVideo: false)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 140)
            }
        }
    }

    private func filterNodeRow(node: FilterNode, isVideo: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { node.enabled },
                set: { viewModel.setFilterNodeEnabled(node.id, enabled: $0) }
            ))
            .toggleStyle(MaterialToggleStyle())
            .labelsHidden()

            Text("\(isVideo ? "V" : "A") · \(node.kind.displayName)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 110, alignment: .leading)

            Text(node.params.isEmpty ? "默认参数" : node.params.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ":"))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("删") { viewModel.removeFilterNode(node.id) }
                .buttonStyle(MaterialActionButtonStyle())
        }
    }

    private var controlColumn: some View {
        VStack(spacing: 12) {
            controlCard
            addTaskBar
        }
        .frame(maxWidth: 620)
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.domain == .video ? "视频格式转换" : "音频格式转换")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            if viewModel.showCopyDisabledHint {
                Text("已启用可视编辑，自动关闭 Copy。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.yellow)
            }

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
                                Button(viewModel.previewTargetFile == file ? "预览中" : "预览") {
                                    viewModel.setPreviewTarget(file)
                                }
                                .buttonStyle(MaterialActionButtonStyle())

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
                .frame(minHeight: 90, maxHeight: 150)
                .background(Color.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var addTaskBar: some View {
        HStack {
            Spacer()
            Button("添加任务") {
                Task { @MainActor in
                    let added = await viewModel.addTasksFromSelection()
                    if added > 0 {
                        selectedSection = .tasks
                    }
                }
            }
            .buttonStyle(MaterialActionButtonStyle())
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

#Preview {
    ConversionWorkspaceView(viewModel: ContentViewModel(), selectedSection: .constant(.videoConvert), targetDomain: .video)
        .padding()
        .background(.ultraThinMaterial)
        .frame(width: 1400, height: 900)
}
