import SwiftUI

/// 单文件媒体编辑工作区：仅处理一个视频文件，支持 metadata、加音轨和加字幕。
struct MediaEditWorkspaceView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 12) {
            fileSection
            outputSection
            streamSection
            metadataSection
            chapterSection
            actionSection
            logSection
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("媒体编辑（单文件）")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            Text("该功能一次只能处理一个视频文件。")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 10) {
                Button("选择视频文件") { viewModel.pickMediaEditVideo() }
                    .buttonStyle(MaterialActionButtonStyle())

                Button("清空") { viewModel.clearMediaEditVideo() }
                    .buttonStyle(MaterialActionButtonStyle())
                    .disabled(viewModel.mediaEditInputVideoURL == nil)

                Picker("输出容器", selection: $viewModel.mediaEditOutputFormat) {
                    ForEach(MediaEditOutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Toggle("覆盖同名文件", isOn: $viewModel.mediaEditOverwriteExisting)
                    .toggleStyle(MaterialToggleStyle())

                Spacer()
            }

            pathLine(
                title: "输入视频",
                path: viewModel.mediaEditInputVideoURL?.path,
                placeholder: "未选择"
            )
        }
        .cardStyle()
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("输出设置")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))

            HStack(spacing: 10) {
                Picker("输出位置", selection: $viewModel.mediaEditOutputLocationMode) {
                    ForEach(MediaEditOutputLocationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                if viewModel.mediaEditOutputLocationMode == .specifiedDirectory {
                    Button("选择输出目录") { viewModel.pickMediaEditOutputDirectory() }
                        .buttonStyle(MaterialActionButtonStyle())
                }

                Spacer()
            }

            pathLine(
                title: "输出目录",
                path: viewModel.mediaEditResolvedOutputDirectory?.path,
                placeholder: viewModel.mediaEditOutputLocationMode == .sourceDirectory ? "将输出到源文件目录" : "未选择"
            )
        }
        .cardStyle()
    }

    private var streamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("流编辑")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))

            HStack(spacing: 10) {
                Button("添加音频流") { viewModel.pickMediaEditAdditionalAudio() }
                    .buttonStyle(MaterialActionButtonStyle())
                Button("移除音频流") { viewModel.clearMediaEditAdditionalAudio() }
                    .buttonStyle(MaterialActionButtonStyle())
                    .disabled(viewModel.mediaEditAdditionalAudioURL == nil)

                Spacer()
            }

            pathLine(
                title: "附加音频",
                path: viewModel.mediaEditAdditionalAudioURL?.path,
                placeholder: "未附加"
            )

            HStack(spacing: 10) {
                Button("添加字幕流") { viewModel.pickMediaEditSubtitle() }
                    .buttonStyle(MaterialActionButtonStyle())
                Button("移除字幕流") { viewModel.clearMediaEditSubtitle() }
                    .buttonStyle(MaterialActionButtonStyle())
                    .disabled(viewModel.mediaEditSubtitleURL == nil)

                Spacer()
            }

            pathLine(
                title: "附加字幕",
                path: viewModel.mediaEditSubtitleURL?.path,
                placeholder: "未附加"
            )
        }
        .cardStyle()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))

            LazyVGrid(
                columns: [GridItem(.flexible(minimum: 220)), GridItem(.flexible(minimum: 220))],
                alignment: .leading,
                spacing: 10
            ) {
                metadataField("Title", text: $viewModel.mediaEditMetadataTitle)
                metadataField("Artist", text: $viewModel.mediaEditMetadataArtist)
                metadataField("Album", text: $viewModel.mediaEditMetadataAlbum)
                metadataField("Year", text: $viewModel.mediaEditMetadataYear)
                metadataField("Genre", text: $viewModel.mediaEditMetadataGenre)
                metadataField("Language", text: $viewModel.mediaEditMetadataLanguage)
                metadataField("Copyright", text: $viewModel.mediaEditMetadataCopyright)
            }

            metadataField("Comment", text: $viewModel.mediaEditMetadataComment)
        }
        .cardStyle()
    }

    private var actionSection: some View {
        HStack {
            Spacer()

            if viewModel.mediaEditIsProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            Button(viewModel.mediaEditIsProcessing ? "处理中..." : "开始媒体编辑") {
                Task { @MainActor in
                    await viewModel.runMediaEdit()
                }
            }
            .buttonStyle(MaterialActionButtonStyle())
            .disabled(!viewModel.canRunMediaEdit)
        }
    }

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chapters")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                Spacer()
                Button("添加章节") { viewModel.addMediaEditChapter() }
                    .buttonStyle(MaterialActionButtonStyle())
                Button("清空章节") { viewModel.clearMediaEditChapters() }
                    .buttonStyle(MaterialActionButtonStyle())
                    .disabled(viewModel.mediaEditChapters.isEmpty)
            }

            Text("时间支持 `秒` 或 `HH:MM:SS(.mmm)`，例如 `75` 或 `00:01:15.500`。")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            if viewModel.mediaEditChapters.isEmpty {
                Text("未添加章节。")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach($viewModel.mediaEditChapters) { $chapter in
                        HStack(spacing: 8) {
                            TextField("开始", text: $chapter.startTime)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)

                            TextField("结束", text: $chapter.endTime)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)

                            TextField("章节标题", text: $chapter.title)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                viewModel.removeMediaEditChapter(chapter.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.white.opacity(0.84))
                            }
                            .buttonStyle(MaterialActionButtonStyle())
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("处理日志")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))

            ScrollView {
                Text(viewModel.mediaEditLogs.isEmpty ? "暂无日志输出" : viewModel.mediaEditLogs)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 180, maxHeight: 260)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .cardStyle()
    }

    private func metadataField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            TextField("选填", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func pathLine(title: String, path: String?, placeholder: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(title)：")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Text(path ?? placeholder)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(path == nil ? 0.62 : 0.86))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    MediaEditWorkspaceView(viewModel: ContentViewModel())
        .padding()
        .background(.ultraThinMaterial)
        .frame(width: 1200, height: 860)
}
