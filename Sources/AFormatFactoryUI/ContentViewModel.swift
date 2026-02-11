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

enum ConversionPreset: String, CaseIterable, Identifiable {
    case highQuality
    case balanced
    case smallSize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highQuality:
            return "高质量"
        case .balanced:
            return "均衡"
        case .smallSize:
            return "小体积"
        }
    }
}

enum VideoEncoderOption: String, CaseIterable, Identifiable {
    case auto
    case h264
    case h265
    case av1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "自动"
        case .h264:
            return "H.264"
        case .h265:
            return "H.265"
        case .av1:
            return "AV1"
        }
    }
}

enum VideoScalePreset: String, CaseIterable, Identifiable {
    case source
    case p2160
    case p1440
    case p1080
    case p720
    case p480

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .source:
            return "保持原始"
        case .p2160:
            return "4K (2160p)"
        case .p1440:
            return "2K (1440p)"
        case .p1080:
            return "1080p"
        case .p720:
            return "720p"
        case .p480:
            return "480p"
        }
    }

    var height: Int? {
        switch self {
        case .source:
            return nil
        case .p2160:
            return 2160
        case .p1440:
            return 1440
        case .p1080:
            return 1080
        case .p720:
            return 720
        case .p480:
            return 480
        }
    }
}

enum VideoPresetOption: String, CaseIterable, Identifiable {
    case none
    case ultrafast
    case superfast
    case veryfast
    case faster
    case fast
    case medium
    case slow
    case slower
    case veryslow

    var id: String { rawValue }

    var displayName: String {
        self == .none ? "默认" : rawValue
    }
}

enum AudioCodecOption: String, CaseIterable, Identifiable {
    case auto
    case aac
    case mp3
    case opus
    case vorbis
    case flac
    case alac
    case pcmS16le

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "自动"
        case .aac:
            return "AAC"
        case .mp3:
            return "MP3 (LAME)"
        case .opus:
            return "Opus"
        case .vorbis:
            return "Vorbis"
        case .flac:
            return "FLAC"
        case .alac:
            return "ALAC"
        case .pcmS16le:
            return "PCM S16LE"
        }
    }

    var ffmpegCodecName: String? {
        switch self {
        case .auto:
            return nil
        case .aac:
            return "aac"
        case .mp3:
            return "libmp3lame"
        case .opus:
            return "libopus"
        case .vorbis:
            return "libvorbis"
        case .flac:
            return "flac"
        case .alac:
            return "alac"
        case .pcmS16le:
            return "pcm_s16le"
        }
    }
}

enum ConversionTaskStatus: String {
    case queued
    case running
    case succeeded
    case failed

    var displayName: String {
        switch self {
        case .queued:
            return "排队中"
        case .running:
            return "执行中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        }
    }
}

enum OutputLocationMode: String, CaseIterable, Identifiable {
    case sourceDirectory
    case specifiedDirectory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sourceDirectory:
            return "源文件目录"
        case .specifiedDirectory:
            return "指定目录"
        }
    }
}

struct ConversionTask: Identifiable {
    let id: UUID
    let createdAt: Date
    let inputURL: URL
    let outputURL: URL
    let format: ConversionFormat
    let domain: ConversionDomain
    let overwriteExisting: Bool
    let extraArguments: [String]
    let optionsSummary: String

    var status: ConversionTaskStatus
    var startedAt: Date?
    var finishedAt: Date?
    var logs: String
}

private struct TaskExecutionContext {
    let id: UUID
    let inputURL: URL
    let outputURL: URL
    let format: ConversionFormat
    let overwriteExisting: Bool
    let extraArguments: [String]
}

actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        count = max(1, value)
    }

    func acquire() async {
        if count > 0 {
            count -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let continuation = waiters.removeFirst()
            continuation.resume()
            return
        }
        count += 1
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var domain: ConversionDomain = .video {
        didSet { ensureFormatMatchesDomain() }
    }

    @Published private(set) var selectedVideoFiles: [URL] = []
    @Published private(set) var selectedAudioFiles: [URL] = []
    @Published var outputLocationMode: OutputLocationMode = .sourceDirectory
    @Published var outputDirectory: URL?
    @Published var format: ConversionFormat = .mp4
    @Published private(set) var supportedFormats: Set<ConversionFormat> = Set(ConversionFormat.allCases)

    @Published var overwriteExistingFiles = true
    @Published var conversionPreset: ConversionPreset = .balanced {
        didSet { applyPreset() }
    }

    // Video advanced settings
    @Published var videoRateControl: VideoRateControl = .constantQuality
    @Published var videoEncoder: VideoEncoderOption = .auto
    @Published var videoScalePreset: VideoScalePreset = .source
    @Published var videoPreset: VideoPresetOption = .medium
    @Published var videoPixelFormat: String = "yuv420p"
    @Published var videoGOP: String = ""
    @Published var videoProfile: String = ""
    @Published var videoLevel: String = ""
    @Published var videoTune: String = ""
    @Published var videoCRF: Double = 23
    @Published var videoBitrateKbps: String = "2500"
    @Published var videoMaxBitrateKbps: String = ""
    @Published var videoBufferSizeKbps: String = ""
    @Published var videoFrameRate: String = ""
    @Published var enableDeinterlace = false

    // Audio advanced settings
    @Published var audioCodec: AudioCodecOption = .auto
    @Published var audioBitrateKbps: String = "192"
    @Published var audioSampleRate: String = "44100"
    @Published var audioChannels: Int = 2
    @Published var audioVolumeDB: String = ""
    @Published var audioVBRQuality: String = ""
    @Published var enableLoudnorm = false

    // General expert settings
    @Published var keepMetadata = true
    @Published var enableFastStart = true
    @Published var startTime: String = ""
    @Published var duration: String = ""
    @Published var threadCount: String = ""
    @Published var customFFmpegArgs: String = ""

    // Queue controls
    @Published var tasks: [ConversionTask] = []
    @Published var selectedTaskID: UUID?
    @Published var maxConcurrentTasks: Int = 2
    @Published var isProcessingQueue = false
    @Published var appLogs = ""

    private let runner = FFmpegRunner()
    private var capabilities: FFmpegCapabilities?

    init() {
        applyPreset()
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

    var selectedTask: ConversionTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first(where: { $0.id == selectedTaskID })
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
            appendAppLog("\(domain.displayName)：已选择 \(selectedFiles.count) 个文件。")
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let directory = panel.url {
            outputDirectory = directory
            appendAppLog("输出目录：\(directory.path)")
        }
    }

    func removeSelectedInputFile(_ file: URL) {
        switch domain {
        case .video:
            selectedVideoFiles.removeAll { $0 == file }
        case .audio:
            selectedAudioFiles.removeAll { $0 == file }
        }
        appendAppLog("已移除输入文件：\(file.lastPathComponent)")
    }

    @discardableResult
    func addTasksFromSelection() -> Int {
        let files = selectedFiles
        guard !files.isEmpty else {
            appendAppLog("请先选择输入文件。")
            return 0
        }

        guard outputLocationMode == .sourceDirectory || outputDirectory != nil else {
            appendAppLog("请先选择输出目录。")
            return 0
        }

        let extraArguments = extraFFmpegArguments()
        let optionsSummary = currentOptionsSummary()

        let newTasks = files.map { file -> ConversionTask in
            let output = outputURL(for: file)
            let lines = [
                "任务已创建。",
                "输入：\(file.path)",
                "输出：\(output.path)",
                "格式：\(format.displayName)",
                "参数：\(optionsSummary)"
            ]

            return ConversionTask(
                id: UUID(),
                createdAt: Date(),
                inputURL: file,
                outputURL: output,
                format: format,
                domain: domain,
                overwriteExisting: overwriteExistingFiles,
                extraArguments: extraArguments,
                optionsSummary: optionsSummary,
                status: .queued,
                startedAt: nil,
                finishedAt: nil,
                logs: lines.joined(separator: "\n")
            )
        }

        tasks.append(contentsOf: newTasks)
        if selectedTaskID == nil {
            selectedTaskID = newTasks.first?.id
        }
        appendAppLog("已添加 \(newTasks.count) 个任务到队列。")
        return newTasks.count
    }

    func startQueuedTasks() async {
        guard !isProcessingQueue else {
            appendAppLog("任务队列正在执行中。")
            return
        }

        let queuedTaskIDs = tasks.filter { $0.status == .queued }.map(\ .id)
        guard !queuedTaskIDs.isEmpty else {
            appendAppLog("没有待执行任务。")
            return
        }

        isProcessingQueue = true
        appendAppLog("开始执行 \(queuedTaskIDs.count) 个任务，并发数：\(maxConcurrentTasks)")

        let semaphore = AsyncSemaphore(value: maxConcurrentTasks)
        await withTaskGroup(of: Void.self) { group in
            for id in queuedTaskIDs {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await semaphore.acquire()
                    await self.runTask(id: id)
                    await semaphore.release()
                }
            }
            await group.waitForAll()
        }

        isProcessingQueue = false
        appendAppLog("队列执行完成。")
    }

    func clearFinishedTasks() {
        tasks.removeAll { $0.status == .succeeded || $0.status == .failed }
        if let selectedTaskID, tasks.contains(where: { $0.id == selectedTaskID }) == false {
            self.selectedTaskID = tasks.first?.id
        }
    }

    private nonisolated func runTask(id: UUID) async {
        guard let context = await MainActor.run(body: { self.prepareTaskForExecution(id: id) }) else {
            return
        }

        do {
            try await FFmpegRunner().transcode(
                input: context.inputURL,
                output: context.outputURL,
                format: context.format,
                overwriteExisting: context.overwriteExisting,
                extraArguments: context.extraArguments
            ) { [weak self] message in
                Task { @MainActor in
                    self?.appendTaskLog(id: context.id, line: message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            await MainActor.run {
                self.markTaskSucceeded(id: context.id)
            }
        } catch {
            await MainActor.run {
                self.markTaskFailed(id: context.id, reason: error.localizedDescription)
            }
        }
    }

    private func prepareTaskForExecution(id: UUID) -> TaskExecutionContext? {
        guard let index = indexOfTask(id: id) else { return nil }
        guard tasks[index].status == .queued else { return nil }

        tasks[index].status = .running
        tasks[index].startedAt = Date()
        appendTaskLog(id: id, line: "开始执行任务...")

        return TaskExecutionContext(
            id: id,
            inputURL: tasks[index].inputURL,
            outputURL: tasks[index].outputURL,
            format: tasks[index].format,
            overwriteExisting: tasks[index].overwriteExisting,
            extraArguments: tasks[index].extraArguments
        )
    }

    private func markTaskSucceeded(id: UUID) {
        guard let index = indexOfTask(id: id) else { return }
        tasks[index].status = .succeeded
        tasks[index].finishedAt = Date()
        appendTaskLog(id: id, line: "任务完成。")
    }

    private func markTaskFailed(id: UUID, reason: String) {
        guard let index = indexOfTask(id: id) else { return }
        tasks[index].status = .failed
        tasks[index].finishedAt = Date()
        appendTaskLog(id: id, line: "任务失败：\(reason)")
    }

    private func appendTaskLog(id: UUID, line: String) {
        guard !line.isEmpty else { return }
        guard let index = indexOfTask(id: id) else { return }

        if tasks[index].logs.isEmpty {
            tasks[index].logs = line
        } else {
            tasks[index].logs += "\n\(line)"
        }
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

    private func outputURL(for file: URL) -> URL {
        let directory = resolvedOutputDirectory(for: file)
        let baseName = file.deletingPathExtension().lastPathComponent
        let ext = format.outputExtension
        var filename = "\(baseName).\(ext)"

        // Avoid overwriting source when output extension is same and destination is source directory.
        let sourceDirMode = outputLocationMode == .sourceDirectory
        if sourceDirMode, file.pathExtension.lowercased() == ext.lowercased() {
            filename = "\(baseName)_converted.\(ext)"
        }

        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private func resolvedOutputDirectory(for file: URL) -> URL {
        switch outputLocationMode {
        case .sourceDirectory:
            return file.deletingLastPathComponent()
        case .specifiedDirectory:
            return outputDirectory ?? file.deletingLastPathComponent()
        }
    }

    private func indexOfTask(id: UUID) -> Int? {
        tasks.firstIndex(where: { $0.id == id })
    }

    private func appendAppLog(_ line: String) {
        guard !line.isEmpty else { return }
        if appLogs.isEmpty {
            appLogs = line
        } else {
            appLogs += "\n\(line)"
        }
    }

    private func extraFFmpegArguments() -> [String] {
        var args: [String] = []
        var videoFilters: [String] = []
        var audioFilters: [String] = []

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
                args += selectedVideoEncoderArguments()
            }

            if format != .gif {
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

            if let fps = parsedPositiveDouble(videoFrameRate) {
                args += ["-r", String(format: "%.2f", fps)]
            }

            if format != .gif, let height = videoScalePreset.height {
                videoFilters.append("scale=-2:\(height):flags=lanczos")
            }
            if enableDeinterlace {
                videoFilters.append("yadif")
            }
        }

        if format != .gif {
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
                audioFilters.append("loudnorm=I=-16:LRA=11:TP=-1.5")
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

    private func applyPreset() {
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

    private func currentOptionsSummary() -> String {
        var segments: [String] = [
            "预设=\(conversionPreset.displayName)",
            "输出=\(outputLocationMode.displayName)",
            "覆盖=\(overwriteExistingFiles ? "是" : "否")"
        ]

        if domain == .video {
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
        }

        if format != .gif {
            segments.append("音频编码=\(audioCodec.displayName)")
            segments.append("音频码率=\(audioBitrateKbps)kbps")
            segments.append("采样率=\(audioSampleRate)")
            segments.append("声道=\(audioChannels)")
        }

        return segments.joined(separator: " | ")
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
