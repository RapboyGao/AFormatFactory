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
    @Published var videoCRF: Double = 23
    @Published var videoBitrateKbps: String = "2500"
    @Published var videoFrameRate: String = ""

    // Audio advanced settings
    @Published var audioBitrateKbps: String = "192"
    @Published var audioSampleRate: String = "44100"
    @Published var audioChannels: Int = 2

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

    func addTasksFromSelection() {
        let files = selectedFiles
        guard !files.isEmpty else {
            appendAppLog("请先选择输入文件。")
            return
        }

        guard let outputDirectory else {
            appendAppLog("请先选择输出目录。")
            return
        }

        let extraArguments = extraFFmpegArguments()
        let optionsSummary = currentOptionsSummary()

        let newTasks = files.map { file -> ConversionTask in
            let output = outputURL(for: file, in: outputDirectory)
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

    private func outputURL(for file: URL, in outputDirectory: URL) -> URL {
        let baseName = file.deletingPathExtension().lastPathComponent
        let ext = format.outputExtension
        let filename = "\(baseName).\(ext)"
        return outputDirectory.appendingPathComponent(filename, isDirectory: false)
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

        if domain == .video {
            if format != .gif {
                args += selectedVideoEncoderArguments()
            }

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

            if format != .gif, let height = videoScalePreset.height {
                args += ["-vf", "scale=-2:\(height):flags=lanczos"]
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
            audioBitrateKbps = "320"
        case .balanced:
            videoRateControl = .constantQuality
            videoCRF = 23
            audioBitrateKbps = "192"
        case .smallSize:
            videoRateControl = .constantQuality
            videoCRF = 30
            audioBitrateKbps = "128"
        }
    }

    private func currentOptionsSummary() -> String {
        var segments: [String] = [
            "预设=\(conversionPreset.displayName)",
            "覆盖=\(overwriteExistingFiles ? "是" : "否")"
        ]

        if domain == .video {
            segments.append("编码器=\(videoEncoder.displayName)")
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
}
