import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AFormatFactory")
                .font(.largeTitle)
                .bold()

            Picker("功能区", selection: $viewModel.domain) {
                ForEach(ConversionDomain.allCases) { domain in
                    Text(domain.displayName).tag(domain)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
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
                .frame(width: 160)

                Button(viewModel.isConverting ? "转换中..." : "开始转换") {
                    Task {
                        await viewModel.startConversion()
                    }
                }
                .disabled(viewModel.isConverting)
            }

            GroupBox("高级参数") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("覆盖同名输出文件", isOn: $viewModel.overwriteExistingFiles)

                    if viewModel.domain == .video {
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

            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.domain.displayName) 输入文件（\(viewModel.selectedFiles.count)）")
                    .font(.headline)
                List(viewModel.selectedFiles, id: \.self) { url in
                    Text(url.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                .frame(height: 170)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("输出目录")
                    .font(.headline)
                Text(viewModel.outputDirectory?.path ?? "未选择")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("日志")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.logs.isEmpty ? "暂无日志" : viewModel.logs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
                .cornerRadius(8)
            }
        }
        .padding(20)
    }
}

#Preview {
    ContentView()
        .frame(width: 860, height: 560)
}
