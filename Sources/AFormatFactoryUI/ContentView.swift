import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AFormatFactory")
                .font(.largeTitle)
                .bold()

            Picker("功能区", selection: $viewModel.domain) {
                ForEach(ConversionDomain.allCases) { domain in
                    Text(domain.displayName).tag(domain)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button("选择输入文件") {
                    viewModel.pickInputFiles()
                }

                Button("选择输出目录") {
                    viewModel.pickOutputDirectory()
                }

                Picker("输出格式", selection: $viewModel.format) {
                    ForEach(viewModel.availableFormats) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                Button("添加任务") {
                    viewModel.addTasksFromSelection()
                }

                Button(viewModel.isProcessingQueue ? "执行中..." : "开始队列") {
                    Task {
                        await viewModel.startQueuedTasks()
                    }
                }
                .disabled(viewModel.isProcessingQueue)

                Button("清理已完成") {
                    viewModel.clearFinishedTasks()
                }

                Spacer()

                Stepper(value: $viewModel.maxConcurrentTasks, in: 1...8) {
                    Text("并发: \(viewModel.maxConcurrentTasks)")
                        .frame(width: 90, alignment: .trailing)
                }
            }

            GroupBox("高级参数") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        LabeledContent("参数预设") {
                            Picker("参数预设", selection: $viewModel.conversionPreset) {
                                ForEach(ConversionPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                        }
                        Spacer()
                    }

                    Toggle("覆盖同名输出文件", isOn: $viewModel.overwriteExistingFiles)

                    if viewModel.domain == .video {
                        HStack(spacing: 12) {
                            LabeledContent("视频编码器") {
                                Picker("视频编码器", selection: $viewModel.videoEncoder) {
                                    ForEach(viewModel.availableVideoEncoders) { encoder in
                                        Text(encoder.displayName).tag(encoder)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 140)
                            }

                            LabeledContent("分辨率") {
                                Picker("分辨率", selection: $viewModel.videoScalePreset) {
                                    ForEach(VideoScalePreset.allCases) { scale in
                                        Text(scale.displayName).tag(scale)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 140)
                            }
                            Spacer()
                        }

                        Picker("视频码控", selection: $viewModel.videoRateControl) {
                            ForEach(VideoRateControl.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 12) {
                            if viewModel.videoRateControl == .constantQuality {
                                HStack(spacing: 8) {
                                    Text("CRF")
                                    Slider(value: $viewModel.videoCRF, in: 16...35, step: 1)
                                    Text("\(Int(viewModel.videoCRF))")
                                        .frame(width: 30, alignment: .trailing)
                                }
                            } else {
                                LabeledContent("视频码率(kbps)") {
                                    TextField("2500", text: $viewModel.videoBitrateKbps)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)
                                }
                            }

                            LabeledContent("帧率(FPS)") {
                                TextField("留空=保持原始", text: $viewModel.videoFrameRate)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 130)
                            }
                        }
                    }

                    HStack(spacing: 12) {
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
                                    .frame(width: 24, alignment: .trailing)
                            }
                            .frame(width: 80)
                        }
                    }
                }
                .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("任务队列（\(viewModel.tasks.count)）")
                        .font(.headline)

                    List(selection: $viewModel.selectedTaskID) {
                        ForEach(viewModel.tasks) { task in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(color(for: task.status))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.inputURL.lastPathComponent)
                                        .lineLimit(1)
                                    Text("→ \(task.outputURL.lastPathComponent) · \(task.format.displayName) · \(task.status.displayName)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                            .tag(task.id)
                        }
                    }
                    .frame(minHeight: 190)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("任务日志")
                        .font(.headline)

                    ScrollView {
                        Text(viewModel.selectedTask?.logs ?? "请在左侧选择任务查看日志")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(minHeight: 190)
                    .background(Color.black.opacity(0.06))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("应用日志")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.appLogs.isEmpty ? "暂无日志" : viewModel.appLogs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
                .cornerRadius(8)
            }
        }
        .padding(18)
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

#Preview {
    ContentView()
        .frame(width: 980, height: 720)
}
