import AppKit
import Foundation
import UniformTypeIdentifiers

enum VideoRateControl: String, CaseIterable, Identifiable {
    case constantQuality
    case targetBitrate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .constantQuality:
            return "恒定质量 (CRF)"
        case .targetBitrate:
            return "目标码率"
        }
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var domain: ConversionDomain = .video {
        didSet { ensureFormatMatchesDomain() }
    }
    @Published private(set) var selectedVideoFiles: [URL] = []
    @Published private(set) var selectedAudioFiles: [URL] = []
    @Published var outputDirectory: URL?
    @Published var format: ConversionFormat = .mp4
    @Published var isConverting = false
    @Published var logs = ""
    @Published private(set) var supportedFormats: Set<ConversionFormat> = Set(ConversionFormat.allCases)
    @Published var overwriteExistingFiles = true

    // Video advanced settings
    @Published var videoRateControl: VideoRateControl = .constantQuality
    @Published var videoCRF: Double = 23
    @Published var videoBitrateKbps: String = "2500"
    @Published var videoFrameRate: String = ""

    // Audio advanced settings
    @Published var audioBitrateKbps: String = "192"
    @Published var audioSampleRate: String = "44100"
    @Published var audioChannels: Int = 2

    private let runner = FFmpegRunner()

    init() {
        Task {
            await refreshSupportedFormats()
        }
    }

    var selectedFiles: [URL] {
        domain == .video ? selectedVideoFiles : selectedAudioFiles
    }

    var availableFormats: [ConversionFormat] {
        ConversionFormat.formats(for: domain).filter { supportedFormats.contains($0) }
    }

    func pickInputFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = supportedInputTypes(for: domain)

        if panel.runModal() == .OK {
            switch domain {
            case .video:
                selectedVideoFiles = panel.urls
            case .audio:
                selectedAudioFiles = panel.urls
            }
            appendLog("\(domain.displayName)：已选择 \(selectedFiles.count) 个文件。")
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let directory = panel.url {
            outputDirectory = directory
            appendLog("输出目录：\(directory.path)")
        }
    }

    func startConversion() async {
        let files = selectedFiles
        guard !files.isEmpty else {
            appendLog("请先选择输入文件。")
            return
        }

        guard let outputDirectory else {
            appendLog("请先选择输出目录。")
            return
        }

        isConverting = true
        defer { isConverting = false }

        for (index, file) in files.enumerated() {
            let output = outputURL(for: file, in: outputDirectory)
            appendLog("[\(index + 1)/\(files.count)] 开始：\(file.lastPathComponent)")

            do {
                let extraArguments = extraFFmpegArguments()
                try await runner.transcode(
                    input: file,
                    output: output,
                    format: format,
                    overwriteExisting: overwriteExistingFiles,
                    extraArguments: extraArguments
                ) { [weak self] message in
                    Task { @MainActor in
                        self?.appendLog(message.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                appendLog("完成：\(output.lastPathComponent)")
            } catch {
                appendLog("失败：\(error.localizedDescription)")
            }
        }

        appendLog("全部任务结束。")
    }

    private func ensureFormatMatchesDomain() {
        if format.domain != domain, let fallback = availableFormats.first {
            format = fallback
        }
    }

    private func refreshSupportedFormats() async {
        do {
            let capabilities = try await runner.detectCapabilities()
            let supported = Set(ConversionFormat.allCases.filter { $0.isSupported(by: capabilities) })
            if supported.isEmpty {
                appendLog("警告：未探测到可用格式，已保留默认列表。")
                return
            }
            supportedFormats = supported
            ensureFormatMatchesDomain()
            appendLog("已按内置 ffmpeg 能力过滤格式，当前可用 \(supported.count) 项。")
        } catch {
            appendLog("读取 ffmpeg 支持格式失败：\(error.localizedDescription)")
        }
    }

    private func supportedInputTypes(for domain: ConversionDomain) -> [UTType] {
        let extensions: [String]
        switch domain {
        case .video:
            extensions = [
                "mp4", "mov", "mkv", "m4v", "avi", "wmv", "flv", "webm",
                "mpeg", "mpg", "ts", "m2ts", "mts", "vob", "ogv", "3gp"
            ]
        case .audio:
            extensions = [
                "mp3", "wav", "m4a", "aac", "flac", "ogg", "opus", "aif",
                "aiff", "caf", "wma", "amr", "mka", "ac3"
            ]
        }
        return extensions.compactMap { UTType(filenameExtension: $0) }
    }

    private func outputURL(for file: URL, in outputDirectory: URL) -> URL {
        let baseName = file.deletingPathExtension().lastPathComponent
        let ext = format.outputExtension
        let filename = "\(baseName).\(ext)"
        return outputDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    private func appendLog(_ line: String) {
        guard !line.isEmpty else { return }
        if logs.isEmpty {
            logs = line
        } else {
            logs += "\n\(line)"
        }
    }

    private func extraFFmpegArguments() -> [String] {
        var args: [String] = []

        if domain == .video {
            if format != .gif {
                switch videoRateControl {
                case .constantQuality:
                    args += ["-crf", "\(Int(videoCRF))"]
                case .targetBitrate:
                    if let bitrate = parsedPositiveInt(videoBitrateKbps) {
                        args += ["-b:v", "\(bitrate)k"]
                    }
                }
            }

            if let fps = parsedPositiveDouble(videoFrameRate) {
                args += ["-r", String(format: "%.2f", fps)]
            }
        }

        if format != .gif {
            if let bitrate = parsedPositiveInt(audioBitrateKbps) {
                args += ["-b:a", "\(bitrate)k"]
            }
            if let sampleRate = parsedPositiveInt(audioSampleRate) {
                args += ["-ar", "\(sampleRate)"]
            }
            if audioChannels > 0 {
                args += ["-ac", "\(audioChannels)"]
            }
        }

        return args
    }

    private func parsedPositiveInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intValue = Int(trimmed), intValue > 0 else { return nil }
        return intValue
    }

    private func parsedPositiveDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let doubleValue = Double(trimmed), doubleValue > 0 else { return nil }
        return doubleValue
    }
}
