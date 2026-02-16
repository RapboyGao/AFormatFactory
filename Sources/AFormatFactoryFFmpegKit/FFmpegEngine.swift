import AVFoundation
import Foundation

public enum FFmpegEngineError: LocalizedError {
    case ffmpegBinaryMissing(path: String)
    case failed(code: Int32, details: String)

    public var errorDescription: String? {
        switch self {
        case let .ffmpegBinaryMissing(path):
            return "未找到 ffmpeg 可执行文件：\(path)。请先运行 Scripts/build_ffmpeg_libs.sh"
        case let .failed(code, details):
            return "ffmpeg 执行失败（退出码 \(code)）：\(details)"
        }
    }
}

public final class FFmpegEngine: FFmpegEngineProtocol, @unchecked Sendable {
    private static var runningProcesses: [UUID: Process] = [:]
    private static let runningLock = NSLock()

    public init() {}

    public func probe(url: URL) async throws -> FFmpegMediaInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let subtitleTracks = try await asset.loadTracks(withMediaType: .subtitle)
        let streamCount = tracks.count + audioTracks.count + subtitleTracks.count
        return FFmpegMediaInfo(
            durationSeconds: durationSeconds.isFinite ? durationSeconds : nil,
            streamCount: streamCount
        )
    }

    public func detectCapabilities() async throws -> FFmpegCapabilities {
        let executable = try ffmpegExecutableURL()
        let muxersOutput = try runAndCapture(executable: executable, arguments: ["-hide_banner", "-muxers"])
        let encodersOutput = try runAndCapture(executable: executable, arguments: ["-hide_banner", "-encoders"])
        return FFmpegCapabilities(
            muxers: parseMuxers(from: muxersOutput),
            encoders: parseEncoders(from: encodersOutput)
        )
    }

    public func execute(job: FFmpegJob, callbacks: FFmpegCallbacks) async throws -> FFmpegResult {
        let executable = try ffmpegExecutableURL()
        let arguments = Self.commandArguments(
            input: job.input,
            output: job.output,
            overwriteExisting: job.overwriteExisting,
            extraArguments: job.arguments
        )

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            callbacks.onLog(.info, text)
            self.emitProgress(from: text, duration: job.estimatedDurationSeconds, totalFrames: job.estimatedTotalFrames, callbacks: callbacks)
        }

        callbacks.onState(.started)
        try process.run()
        register(process: process, for: job.id)
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        unregister(jobID: job.id)

        if process.terminationReason == .uncaughtSignal {
            callbacks.onState(.cancelled)
            throw FFmpegEngineError.failed(code: process.terminationStatus, details: arguments.joined(separator: " "))
        }

        guard process.terminationStatus == 0 else {
            callbacks.onState(.failed("exit=\(process.terminationStatus)"))
            throw FFmpegEngineError.failed(code: process.terminationStatus, details: arguments.joined(separator: " "))
        }

        callbacks.onProgress(FFmpegProgress(estimatedRatio: 1))
        callbacks.onState(.completed)
        return FFmpegResult(exitCode: process.terminationStatus)
    }

    public func cancel(jobID: UUID) {
        Self.runningLock.lock()
        let process = Self.runningProcesses[jobID]
        Self.runningLock.unlock()
        process?.terminate()
    }

    public static func commandArguments(
        input: URL,
        output: URL,
        overwriteExisting: Bool,
        extraArguments: [String]
    ) -> [String] {
        let overwriteFlag = overwriteExisting ? "-y" : "-n"
        return [overwriteFlag, "-i", input.path] + extraArguments + [output.path]
    }

    public static func commandString(executable: String = "ffmpeg", arguments: [String]) -> String {
        ([executable] + arguments).map { shellEscaped($0) }.joined(separator: " ")
    }

    private static func shellEscaped(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let chars = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "'\"\\$`!"))
        if value.rangeOfCharacter(from: chars) == nil {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func ffmpegExecutableURL() throws -> URL {
        if let explicit = ProcessInfo.processInfo.environment["AFORMATFACTORY_FFMPEG_BIN"], !explicit.isEmpty {
            let url = URL(fileURLWithPath: explicit)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
            throw FFmpegEngineError.ffmpegBinaryMissing(path: url.path)
        }

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let bundled = bundleURL.appendingPathComponent("Contents/Resources/bin/ffmpeg", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let local = cwd.appendingPathComponent("ThirdParty/ffmpeg-install/bin/ffmpeg", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: local.path) {
            return local
        }

        throw FFmpegEngineError.ffmpegBinaryMissing(path: local.path)
    }

    private func runAndCapture(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw FFmpegEngineError.failed(code: process.terminationStatus, details: "无法解析 ffmpeg 输出")
        }
        guard process.terminationStatus == 0 else {
            throw FFmpegEngineError.failed(code: process.terminationStatus, details: output)
        }
        return output
    }

    private func parseMuxers(from output: String) -> Set<String> {
        var result = Set<String>()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(" E ") || trimmed.hasPrefix("E ") || trimmed.hasPrefix("Ed ") else {
                continue
            }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let raw = String(fields[1])
            let primary = raw.split(separator: ",").first.map(String.init) ?? raw
            result.insert(primary.lowercased())
        }
        return result
    }

    private func parseEncoders(from output: String) -> Set<String> {
        var result = Set<String>()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let first = trimmed.first, first == "V" || first == "A" else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            result.insert(String(fields[1]).lowercased())
        }
        return result
    }

    private func emitProgress(from chunk: String, duration: Double?, totalFrames: Double?, callbacks: FFmpegCallbacks) {
        let lines = chunk.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for tokenLine in lines {
            let line = String(tokenLine)
            if line.contains("progress=end") {
                callbacks.onProgress(FFmpegProgress(estimatedRatio: 1))
                continue
            }

            var progress = FFmpegProgress()
            if let t = tokenValue(for: "out_time=", in: line) ?? tokenValue(for: "time=", in: line),
               let elapsed = parseTimeToSeconds(t)
            {
                let ratio = duration.flatMap { $0 > 0 ? max(0, min(1, elapsed / $0)) : nil }
                progress = FFmpegProgress(processedTimeSeconds: elapsed, estimatedRatio: ratio)
                callbacks.onProgress(progress)
                continue
            }

            if let frameToken = tokenValue(for: "frame=", in: line),
               let frame = Double(frameToken)
            {
                let ratio = totalFrames.flatMap { $0 > 0 ? max(0, min(1, frame / $0)) : nil }
                callbacks.onProgress(FFmpegProgress(processedFrames: frame, estimatedRatio: ratio))
            }
        }
    }

    private func tokenValue(for key: String, in line: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        var tail = line[range.upperBound...]
        while let first = tail.first, first == " " {
            tail.removeFirst()
        }
        let token = tail.prefix { !$0.isWhitespace }
        guard !token.isEmpty else { return nil }
        let value = String(token)
        return value == "N/A" ? nil : value
    }

    private func parseTimeToSeconds(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        if parts.count == 3 {
            guard let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else {
                return nil
            }
            return h * 3600 + m * 60 + s
        }
        return Double(value)
    }

    private func register(process: Process, for jobID: UUID) {
        Self.runningLock.lock()
        Self.runningProcesses[jobID] = process
        Self.runningLock.unlock()
    }

    private func unregister(jobID: UUID) {
        Self.runningLock.lock()
        Self.runningProcesses.removeValue(forKey: jobID)
        Self.runningLock.unlock()
    }
}
