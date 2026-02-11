import SwiftUI

public struct PreviewEditorWindowView: View {
    @ObservedObject var viewModel: ContentViewModel
    @StateObject private var previewSession = PreviewSessionStore()

    public init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            previewPicker

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
                AudioPreviewView(
                    url: viewModel.previewTargetFile,
                    isPlaying: $viewModel.isPreviewPlaying,
                    playhead: $viewModel.previewPlayheadSeconds
                )
            }

            TimelineStripView(
                totalDuration: previewSession.durationSeconds,
                start: $viewModel.previewTimeRangeStart,
                end: $viewModel.previewTimeRangeEnd,
                playhead: $viewModel.previewPlayheadSeconds
            )

            filterGraphEditor
        }
        .padding(12)
        .background(backgroundLayer)
        .onAppear {
            viewModel.refreshPreviewTargetIfNeeded()
            viewModel.applyParametersToPreview()
        }
        .onChange(of: viewModel.previewCropRect) { _, _ in viewModel.syncPreviewToParameters() }
        .onChange(of: viewModel.previewTransformState) { _, _ in viewModel.syncPreviewToParameters() }
        .onChange(of: viewModel.previewTimeRangeStart) { _, _ in viewModel.syncPreviewToParameters() }
        .onChange(of: viewModel.previewTimeRangeEnd) { _, _ in viewModel.syncPreviewToParameters() }
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

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("预览编辑")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Picker("编辑模式", selection: $viewModel.editorMode) {
                ForEach(PreviewEditorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

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
    }

    private var previewPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("预览目标")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                if viewModel.domain == .video {
                    HStack(spacing: 6) {
                        Text("裁剪比例")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        ForEach(PreviewAspectPreset.allCases) { preset in
                            Button(preset.displayName) { viewModel.previewAspectPreset = preset }
                                .buttonStyle(MaterialActionButtonStyle())
                        }
                        Button("重置裁剪") {
                            viewModel.pushPreviewSnapshot()
                            viewModel.previewCropRect = .full
                        }
                        .buttonStyle(MaterialActionButtonStyle())
                    }
                }

                Spacer()
            }

            if viewModel.selectedFiles.isEmpty {
                Text("当前功能区还没有输入文件")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.selectedFiles, id: \.self) { file in
                            Button(viewModel.previewTargetFile == file ? "\(file.lastPathComponent) ✓" : file.lastPathComponent) {
                                viewModel.setPreviewTarget(file)
                            }
                            .buttonStyle(MaterialActionButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var filterGraphEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("滤镜链")
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Button("+视频滤镜") { viewModel.addFilterNode(FilterNode(kind: .eq)) }
                    .buttonStyle(MaterialActionButtonStyle())

                Button("+音频滤镜") { viewModel.addFilterNode(FilterNode(kind: .highpass)) }
                    .buttonStyle(MaterialActionButtonStyle())

                Spacer()
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
                .frame(minHeight: 80, maxHeight: 180)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .frame(width: 120, alignment: .leading)

            Text(node.params.isEmpty ? "默认参数" : node.params.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ":"))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("删") { viewModel.removeFilterNode(node.id) }
                .buttonStyle(MaterialActionButtonStyle())
        }
    }

    private var backgroundLayer: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }
}

#Preview {
    PreviewEditorWindowView(viewModel: ContentViewModel())
        .frame(width: 1200, height: 860)
}
