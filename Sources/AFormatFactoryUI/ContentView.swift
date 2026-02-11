import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case videoConvert
    case audioConvert
    case tasks
    case appLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videoConvert:
            return "视频格式转换"
        case .audioConvert:
            return "音频格式转换"
        case .tasks:
            return "任务队列"
        case .appLog:
            return "应用日志"
        }
    }

    var symbol: String {
        switch self {
        case .videoConvert:
            return "film.stack"
        case .audioConvert:
            return "waveform"
        case .tasks:
            return "list.bullet.rectangle"
        case .appLog:
            return "doc.text.magnifyingglass"
        }
    }
}

public struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var selectedSection: WorkspaceSection? = .videoConvert

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .background(backgroundLayer)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
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

    @ViewBuilder
    private var detailView: some View {
        VStack(spacing: 12) {
            switch selectedSection ?? .videoConvert {
            case .videoConvert:
                controlCard
                    .onAppear { viewModel.domain = .video }
                addTaskBar
            case .audioConvert:
                controlCard
                    .onAppear { viewModel.domain = .audio }
                addTaskBar
            case .tasks:
                taskWorkspace
            case .appLog:
                appLogCard
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.domain == .video ? "视频格式转换" : "音频格式转换")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Button("选择输入文件") { viewModel.pickInputFiles() }
                    .buttonStyle(.borderedProminent)

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
                .frame(width: 130)

                if viewModel.outputLocationMode == .specifiedDirectory {
                    Button("选择输出目录") { viewModel.pickOutputDirectory() }
                        .buttonStyle(.bordered)
                }

                Spacer()
            }

            if viewModel.outputLocationMode == .sourceDirectory {
                Text("输出目录：源文件所在目录（每个任务按各自源文件目录输出）")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                if let output = viewModel.outputDirectory {
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

            Divider().overlay(.white.opacity(0.2))

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

            Divider().overlay(.white.opacity(0.2))

            parameterEditor
        }
        .cardStyle()
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
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var parameterEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("高级参数")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            HStack(spacing: 12) {
                LabeledContent("参数预设") {
                    Picker("参数预设", selection: $viewModel.conversionPreset) {
                        ForEach(ConversionPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 150)
                }

                Toggle("覆盖同名文件", isOn: $viewModel.overwriteExistingFiles)
                    .toggleStyle(.switch)
                Toggle("保留元数据", isOn: $viewModel.keepMetadata)
                    .toggleStyle(.switch)
                Toggle("FastStart", isOn: $viewModel.enableFastStart)
                    .toggleStyle(.switch)

                Spacer()
            }

            if viewModel.domain == .video {
                HStack(spacing: 12) {
                    LabeledContent("视频编码器") {
                        Picker("视频编码器", selection: $viewModel.videoEncoder) {
                            ForEach(viewModel.availableVideoEncoders) { encoder in
                                Text(encoder.displayName).tag(encoder)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 145)
                    }

                    LabeledContent("编码预设") {
                        Picker("编码预设", selection: $viewModel.videoPreset) {
                            ForEach(VideoPresetOption.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 110)
                    }

                    LabeledContent("分辨率") {
                        Picker("分辨率", selection: $viewModel.videoScalePreset) {
                            ForEach(VideoScalePreset.allCases) { scale in
                                Text(scale.displayName).tag(scale)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 145)
                    }

                    Picker("视频码控", selection: $viewModel.videoRateControl) {
                        ForEach(VideoRateControl.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Spacer()
                }

                HStack(spacing: 12) {
                    if viewModel.videoRateControl == .constantQuality {
                        HStack(spacing: 8) {
                            Text("CRF")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Slider(value: $viewModel.videoCRF, in: 16...35, step: 1)
                            Text("\(Int(viewModel.videoCRF))")
                                .frame(width: 26, alignment: .trailing)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                        .frame(maxWidth: 300)
                    } else {
                        LabeledContent("视频码率(kbps)") {
                            TextField("2500", text: $viewModel.videoBitrateKbps)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }
                    }

                    LabeledContent("帧率") {
                        TextField("留空=原始", text: $viewModel.videoFrameRate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    LabeledContent("GOP") {
                        TextField("如 60", text: $viewModel.videoGOP)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                    LabeledContent("像素格式") {
                        TextField("yuv420p", text: $viewModel.videoPixelFormat)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                    LabeledContent("Profile") {
                        TextField("high/main", text: $viewModel.videoProfile)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    LabeledContent("Level") {
                        TextField("4.1", text: $viewModel.videoLevel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    LabeledContent("Tune") {
                        TextField("film/animation", text: $viewModel.videoTune)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                    }
                    Toggle("去隔行", isOn: $viewModel.enableDeinterlace)
                        .toggleStyle(.switch)
                    Spacer()
                }

                HStack(spacing: 12) {
                    LabeledContent("最大码率(kbps)") {
                        TextField("选填", text: $viewModel.videoMaxBitrateKbps)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    LabeledContent("缓冲(kbps)") {
                        TextField("选填", text: $viewModel.videoBufferSizeKbps)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                LabeledContent("音频编码器") {
                    Picker("音频编码器", selection: $viewModel.audioCodec) {
                        ForEach(AudioCodecOption.allCases) { codec in
                            Text(codec.displayName).tag(codec)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 130)
                }

                LabeledContent("音频码率(kbps)") {
                    TextField("192", text: $viewModel.audioBitrateKbps)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                LabeledContent("采样率(Hz)") {
                    TextField("44100", text: $viewModel.audioSampleRate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                LabeledContent("声道") {
                    Stepper(value: $viewModel.audioChannels, in: 1...8) {
                        Text("\(viewModel.audioChannels)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .frame(width: 22, alignment: .trailing)
                    }
                    .frame(width: 70)
                }

                LabeledContent("VBR质量") {
                    TextField("0~9", text: $viewModel.audioVBRQuality)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }

                LabeledContent("音量(dB)") {
                    TextField("如 -3 / 2.5", text: $viewModel.audioVolumeDB)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 95)
                }

                Toggle("响度标准化", isOn: $viewModel.enableLoudnorm)
                    .toggleStyle(.switch)

                Spacer()
            }

            HStack(spacing: 12) {
                LabeledContent("开始时间") {
                    TextField("00:00:05 或 5", text: $viewModel.startTime)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
                LabeledContent("时长") {
                    TextField("00:01:30 或 90", text: $viewModel.duration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
                LabeledContent("线程数") {
                    TextField("留空=自动", text: $viewModel.threadCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("自定义 FFmpeg 参数（会追加到命令末尾，空格分隔）")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                TextField("例如: -metadata title=Demo -shortest", text: $viewModel.customFFmpegArgs)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 2)
    }

    private var taskWorkspace: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("任务队列")
                        .font(.system(size: 15, weight: .bold, design: .rounded))

                    Spacer()

                    Button(viewModel.isProcessingQueue ? "执行中..." : "开始队列") {
                        Task { await viewModel.startQueuedTasks() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isProcessingQueue)

                    Button("清理已完成") { viewModel.clearFinishedTasks() }
                        .buttonStyle(.bordered)

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

    private var appLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("应用日志")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            ScrollView {
                Text(viewModel.appLogs.isEmpty ? "暂无日志" : viewModel.appLogs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(minHeight: 420)
        }
        .cardStyle(padding: 12)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.09, blue: 0.16),
                Color(red: 0.10, green: 0.20, blue: 0.30),
                Color(red: 0.03, green: 0.06, blue: 0.11)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func count(for status: ConversionTaskStatus) -> Int {
        viewModel.tasks.filter { $0.status == status }.count
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

private extension View {
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 860)
}
