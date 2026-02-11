import Foundation

extension ContentViewModel {
    var availableVideoEncoders: [VideoEncoderOption] {
        guard let capabilities else { return VideoEncoderOption.allCases }

        var result: [VideoEncoderOption] = [.auto]
        if hasAnyEncoder(["libx264", "h264_videotoolbox", "mpeg4"], in: capabilities) {
            result.append(.h264)
        }
        if hasAnyEncoder(["libx265", "hevc_videotoolbox"], in: capabilities) {
            result.append(.h265)
        }
        if hasAnyEncoder(["libsvtav1", "libaom-av1", "librav1e"], in: capabilities) {
            result.append(.av1)
        }
        return result
    }

    func ensureFormatMatchesDomain() {
        if format.domain != domain, let fallback = availableFormats.first {
            format = fallback
        }
    }

    func refreshSupportedFormats() async {
        do {
            let capabilities = try await runner.detectCapabilities()
            let supported = Set(ConversionFormat.allCases.filter { $0.isSupported(by: capabilities) })
            if supported.isEmpty {
                appendAppLog("警告：未探测到可用格式，已保留默认列表。")
                return
            }
            self.capabilities = capabilities
            supportedFormats = supported
            ensureVideoEncoderIsSupported()
            ensureFormatMatchesDomain()
            appendAppLog("已按内置 ffmpeg 能力过滤格式，当前可用 \(supported.count) 项。")
        } catch {
            appendAppLog("读取 ffmpeg 支持格式失败：\(error.localizedDescription)")
        }
    }

    func extraFFmpegArguments() -> [String] {
        var args: [String] = []
        var videoFilters: [String] = []
        var audioFilters: [String] = []

        if let audioTrack = parsedNonNegativeInt(selectedAudioTrackIndex) {
            if domain == .video {
                args += ["-map", "0:v?", "-map", "0:a:\(audioTrack)", "-map", "0:s?"]
            } else {
                args += ["-map", "0:a:\(audioTrack)"]
            }
        }

        if let ss = parsedTimeValue(startTime) {
            args += ["-ss", ss]
        }
        if let t = parsedTimeValue(duration) {
            args += ["-t", t]
        }
        if let threads = parsedPositiveInt(threadCount) {
            args += ["-threads", "\(threads)"]
        }
        if keepMetadata == false {
            args += ["-map_metadata", "-1"]
        }

        if domain == .video {
            if format != .gif {
                if copyVideoStream {
                    args += ["-c:v", "copy"]
                } else {
                    args += selectedVideoEncoderArguments()

                    if videoPreset != .none {
                        args += ["-preset", videoPreset.rawValue]
                    }
                    if let gop = parsedPositiveInt(videoGOP) {
                        args += ["-g", "\(gop)"]
                    }
                    if let maxrate = parsedPositiveInt(videoMaxBitrateKbps) {
                        args += ["-maxrate", "\(maxrate)k"]
                    }
                    if let buf = parsedPositiveInt(videoBufferSizeKbps) {
                        args += ["-bufsize", "\(buf)k"]
                    }
                    if let profile = nonEmpty(videoProfile) {
                        args += ["-profile:v", profile]
                    }
                    if let level = nonEmpty(videoLevel) {
                        args += ["-level:v", level]
                    }
                    if let tune = nonEmpty(videoTune) {
                        args += ["-tune", tune]
                    }
                    if let pixFmt = nonEmpty(videoPixelFormat) {
                        args += ["-pix_fmt", pixFmt]
                    }
                    switch videoRateControl {
                    case .constantQuality:
                        args += ["-crf", "\(Int(videoCRF))"]
                    case .targetBitrate:
                        if let bitrate = parsedPositiveInt(videoBitrateKbps) {
                            args += ["-b:v", "\(bitrate)k"]
                        }
                    }
                }
            }

            if !copyVideoStream, let fps = parsedPositiveDouble(videoFrameRate) {
                args += ["-r", String(format: "%.2f", fps)]
            }

            if !copyVideoStream, format != .gif, let height = videoScalePreset.height {
                videoFilters.append("scale=-2:\(height):flags=lanczos")
            }
            if !copyVideoStream, enableDeinterlace {
                videoFilters.append("yadif")
            }
            if !copyVideoStream {
                switch videoRotate {
                case .none:
                    break
                case .clockwise90:
                    videoFilters.append("transpose=1")
                case .counterClockwise90:
                    videoFilters.append("transpose=2")
                case .rotate180:
                    videoFilters.append("transpose=2,transpose=2")
                }
                if videoFlipHorizontal {
                    videoFilters.append("hflip")
                }
                if videoFlipVertical {
                    videoFilters.append("vflip")
                }
                if
                    let cropW = parsedPositiveInt(videoCropWidth),
                    let cropH = parsedPositiveInt(videoCropHeight)
                {
                    let cropX = parsedNonNegativeInt(videoCropX) ?? 0
                    let cropY = parsedNonNegativeInt(videoCropY) ?? 0
                    videoFilters.append("crop=\(cropW):\(cropH):\(cropX):\(cropY)")
                }
            }
        }

        if format != .gif {
            if copyAudioStream {
                args += ["-c:a", "copy"]
            } else {
                if let codec = audioCodec.ffmpegCodecName {
                    args += ["-c:a", codec]
                }
                if let bitrate = parsedPositiveInt(audioBitrateKbps) {
                    args += ["-b:a", "\(bitrate)k"]
                }
                if let sampleRate = parsedPositiveInt(audioSampleRate) {
                    args += ["-ar", "\(sampleRate)"]
                }
                if audioChannels > 0 {
                    args += ["-ac", "\(audioChannels)"]
                }
                if let q = parsedBoundedDouble(audioVBRQuality, min: 0, max: 9) {
                    args += ["-q:a", String(format: "%.1f", q)]
                }
                if let vol = parsedDouble(audioVolumeDB), vol != 0 {
                    audioFilters.append("volume=\(String(format: "%.2f", vol))dB")
                }
                if enableLoudnorm {
                    let i = parsedBoundedDouble(loudnormIntegratedTarget, min: -70, max: -5) ?? -16
                    let lra = parsedBoundedDouble(loudnormLraTarget, min: 1, max: 20) ?? 11
                    let tp = parsedBoundedDouble(loudnormTruePeakTarget, min: -9, max: 0) ?? -1.5
                    audioFilters.append(
                        "loudnorm=I=\(String(format: "%.1f", i)):LRA=\(String(format: "%.1f", lra)):TP=\(String(format: "%.1f", tp))"
                    )
                }
            }
        }

        if !videoFilters.isEmpty {
            args += ["-vf", videoFilters.joined(separator: ",")]
        }
        if !audioFilters.isEmpty {
            args += ["-af", audioFilters.joined(separator: ",")]
        }

        if enableFastStart, domain == .video, [.mp4, .mov, .m4v].contains(format) {
            args += ["-movflags", "+faststart"]
        }

        if let custom = splitCustomArgs(customFFmpegArgs), !custom.isEmpty {
            args += custom
        }

        return args
    }

    func applyPreset() {
        switch conversionPreset {
        case .highQuality:
            videoRateControl = .constantQuality
            videoCRF = 18
            videoPreset = .slow
            audioBitrateKbps = "320"
        case .balanced:
            videoRateControl = .constantQuality
            videoCRF = 23
            videoPreset = .medium
            audioBitrateKbps = "192"
        case .smallSize:
            videoRateControl = .constantQuality
            videoCRF = 30
            videoPreset = .faster
            audioBitrateKbps = "128"
        }
    }

    func currentOptionsSummary() -> String {
        var segments: [String] = [
            "预设=\(conversionPreset.displayName)",
            "输出=\(outputLocationMode.displayName)",
            "覆盖=\(overwriteExistingFiles ? "是" : "否")"
        ]

        if domain == .video {
            if copyVideoStream {
                segments.append("视频流=Copy")
            } else {
                segments.append("编码器=\(videoEncoder.displayName)")
                segments.append("预设=\(videoPreset.displayName)")
                segments.append("分辨率=\(videoScalePreset.displayName)")
                switch videoRateControl {
                case .constantQuality:
                    segments.append("CRF=\(Int(videoCRF))")
                case .targetBitrate:
                    segments.append("视频码率=\(videoBitrateKbps)kbps")
                }
                if !videoFrameRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("FPS=\(videoFrameRate)")
                }
                if videoRotate != .none {
                    segments.append("旋转=\(videoRotate.displayName)")
                }
                if videoFlipHorizontal || videoFlipVertical {
                    segments.append("翻转=\(videoFlipHorizontal ? "H" : "")\(videoFlipVertical ? "V" : "")")
                }
            }
        }

        if format != .gif {
            if copyAudioStream {
                segments.append("音频流=Copy")
            } else {
                segments.append("音频编码=\(audioCodec.displayName)")
                segments.append("音频码率=\(audioBitrateKbps)kbps")
                segments.append("采样率=\(audioSampleRate)")
                segments.append("声道=\(audioChannels)")
                if enableLoudnorm {
                    segments.append("响度=\(loudnormIntegratedTarget)/\(loudnormLraTarget)/\(loudnormTruePeakTarget)")
                }
            }
        }
        if !selectedAudioTrackIndex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append("音轨=\(selectedAudioTrackIndex)")
        }

        return segments.joined(separator: " | ")
    }

    private func selectedVideoEncoderArguments() -> [String] {
        switch videoEncoder {
        case .auto:
            return []
        case .h264:
            if hasAnyEncoder(["libx264"]) { return ["-c:v", "libx264"] }
            if hasAnyEncoder(["h264_videotoolbox"]) { return ["-c:v", "h264_videotoolbox"] }
            if hasAnyEncoder(["mpeg4"]) { return ["-c:v", "mpeg4"] }
        case .h265:
            if hasAnyEncoder(["libx265"]) { return ["-c:v", "libx265"] }
            if hasAnyEncoder(["hevc_videotoolbox"]) { return ["-c:v", "hevc_videotoolbox"] }
        case .av1:
            if hasAnyEncoder(["libsvtav1"]) { return ["-c:v", "libsvtav1"] }
            if hasAnyEncoder(["libaom-av1"]) { return ["-c:v", "libaom-av1"] }
            if hasAnyEncoder(["librav1e"]) { return ["-c:v", "librav1e"] }
        }
        return []
    }

    private func hasAnyEncoder(_ names: [String], in capabilities: FFmpegCapabilities? = nil) -> Bool {
        let source = capabilities ?? self.capabilities
        guard let source else { return false }
        return names.contains { source.encoders.contains($0) }
    }

    private func ensureVideoEncoderIsSupported() {
        if !availableVideoEncoders.contains(videoEncoder) {
            videoEncoder = .auto
        }
    }

    private func parsedPositiveInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intValue = Int(trimmed), intValue > 0 else { return nil }
        return intValue
    }

    private func parsedNonNegativeInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intValue = Int(trimmed), intValue >= 0 else { return nil }
        return intValue
    }

    private func parsedPositiveDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let doubleValue = Double(trimmed), doubleValue > 0 else { return nil }
        return doubleValue
    }

    private func parsedDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let doubleValue = Double(trimmed) else { return nil }
        return doubleValue
    }

    private func parsedBoundedDouble(_ value: String, min: Double, max: Double) -> Double? {
        guard let d = parsedDouble(value), d >= min, d <= max else { return nil }
        return d
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parsedTimeValue(_ value: String) -> String? {
        nonEmpty(value)
    }

    private func splitCustomArgs(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
