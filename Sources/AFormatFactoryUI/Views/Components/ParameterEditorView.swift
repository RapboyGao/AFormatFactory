import SwiftUI

struct ParameterEditorView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("高级参数")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Picker("参数预设", selection: $viewModel.conversionPreset) {
                    ForEach(ConversionPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }

            sectionTitle("基础")
            HStack(spacing: 12) {
                Toggle("覆盖同名文件", isOn: $viewModel.overwriteExistingFiles)
                    .toggleStyle(MaterialToggleStyle())
                Toggle("保留元数据", isOn: $viewModel.keepMetadata)
                    .toggleStyle(MaterialToggleStyle())
                Toggle("FastStart", isOn: $viewModel.enableFastStart)
                    .toggleStyle(MaterialToggleStyle())

                Spacer()
            }

            if viewModel.domain == .video {
                Divider().overlay(.white.opacity(0.18))
                HStack {
                    sectionTitle("视频参数")
                    Toggle("视频流 Copy", isOn: $viewModel.copyVideoStream)
                        .toggleStyle(MaterialToggleStyle())
                    Spacer()
                }

                if viewModel.copyVideoStream {
                    Text("视频流将直接复制（`-c:v copy`），已隐藏重编码参数。")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                } else {
                    HStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            parameterField("视频编码器", width: 100) {
                                Picker("视频编码器", selection: $viewModel.videoEncoder)
                                {
                                    ForEach(viewModel.availableVideoEncoders) {
                                        encoder in
                                        Text(encoder.displayName).tag(encoder)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }

                            parameterField("编码预设", width: 110) {
                                Picker("编码预设", selection: $viewModel.videoPreset) {
                                    ForEach(VideoPresetOption.allCases) { preset in
                                        Text(preset.displayName).tag(preset)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }

                            parameterField("分辨率", width: 100) {
                                Picker(
                                    "分辨率",
                                    selection: $viewModel.videoScalePreset
                                ) {
                                    ForEach(VideoScalePreset.allCases) { scale in
                                        Text(scale.displayName).tag(scale)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    sectionTitle("视频码控")
                    HStack(spacing: 0) {
                        VideoRateControlSegmentedControl(
                            selection: $viewModel.videoRateControl
                        )
                        .frame(width: 420, alignment: .leading)
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        if viewModel.videoRateControl == .constantQuality {
                            parameterField("CRF", width: 300) {
                                HStack(spacing: 8) {
                                    Slider(
                                        value: $viewModel.videoCRF,
                                        in: 16...35,
                                        step: 1
                                    )
                                    Text("\(Int(viewModel.videoCRF))")
                                        .frame(width: 26, alignment: .trailing)
                                        .font(
                                            .system(
                                                size: 13,
                                                weight: .bold,
                                                design: .monospaced
                                            )
                                        )
                                }
                            }
                        } else {
                            parameterField("视频码率(kbps)", width: 110) {
                                TextField("2500", text: $viewModel.videoBitrateKbps)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                            }
                        }

                        parameterField("帧率", width: 110) {
                            TextField("留空=原始", text: $viewModel.videoFrameRate)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }

                        parameterField("最大码率(kbps)", width: 100) {
                            TextField("选填", text: $viewModel.videoMaxBitrateKbps)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        parameterField("缓冲(kbps)", width: 100) {
                            TextField("选填", text: $viewModel.videoBufferSizeKbps)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        Spacer()
                    }

                    HStack(alignment: .top, spacing: 12) {
                        parameterField("GOP", width: 90) {
                            TextField("如 60", text: $viewModel.videoGOP)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                        parameterField("像素格式", width: 110) {
                            TextField("yuv420p", text: $viewModel.videoPixelFormat)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }
                        parameterField("Profile", width: 100) {
                            TextField("high/main", text: $viewModel.videoProfile)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                        parameterField("Level", width: 70) {
                            TextField("4.1", text: $viewModel.videoLevel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                        parameterField("Tune", width: 130) {
                            TextField("film/animation", text: $viewModel.videoTune)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)
                        }
                        parameterField("去隔行", width: 80) {
                            Toggle("", isOn: $viewModel.enableDeinterlace)
                                .toggleStyle(MaterialToggleStyle())
                                .labelsHidden()
                        }
                        Spacer()
                    }
                }
            }

            Divider().overlay(.white.opacity(0.18))
            HStack {
                sectionTitle("音频参数")
                Toggle("音频流 Copy", isOn: $viewModel.copyAudioStream)
                    .toggleStyle(MaterialToggleStyle())
                Spacer()
            }

            if viewModel.copyAudioStream {
                Text("音频流将直接复制（`-c:a copy`），已隐藏重编码参数。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            } else {
                HStack(alignment: .top, spacing: 12) {
                    parameterField("音频编码器", width: 130) {
                        Picker("音频编码器", selection: $viewModel.audioCodec) {
                            ForEach(AudioCodecOption.allCases) { codec in
                                Text(codec.displayName).tag(codec)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 130)
                    }

                    parameterField("音频码率(kbps)", width: 120) {
                        TextField("192", text: $viewModel.audioBitrateKbps)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    parameterField("采样率(Hz)", width: 120) {
                        TextField("44100", text: $viewModel.audioSampleRate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    parameterField("声道", width: 70) {
                        Stepper(value: $viewModel.audioChannels, in: 1...8) {
                            Text("\(viewModel.audioChannels)")
                                .font(
                                    .system(
                                        size: 13,
                                        weight: .bold,
                                        design: .monospaced
                                    )
                                )
                                .frame(width: 22, alignment: .trailing)
                        }
                        .frame(width: 70)
                    }

                    parameterField("VBR质量", width: 80) {
                        TextField("0~9", text: $viewModel.audioVBRQuality)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    parameterField("音量(dB)", width: 105) {
                        TextField("如 -3 / 2.5", text: $viewModel.audioVolumeDB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 105)
                    }

                    parameterField("响度标准化", width: 92) {
                        Toggle("", isOn: $viewModel.enableLoudnorm)
                            .toggleStyle(MaterialToggleStyle())
                            .labelsHidden()
                    }

                    Spacer()
                }
            }

            Divider().overlay(.white.opacity(0.18))
            sectionTitle("专家参数")

            HStack(spacing: 12) {
                parameterField("开始时间", width: 130) {
                    TextField("00:00:05 或 5", text: $viewModel.startTime)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
                parameterField("时长", width: 130) {
                    TextField("00:01:30 或 90", text: $viewModel.duration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
                parameterField("线程数", width: 110) {
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
                TextField(
                    "例如: -metadata title=Demo -shortest",
                    text: $viewModel.customFFmpegArgs
                )
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 2)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .textCase(.uppercase)
    }

    private func parameterField<Content: View>(
        _ title: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            content()
        }
        .frame(width: width, alignment: .leading)
    }
}
