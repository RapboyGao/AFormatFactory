import Foundation

struct FFmpegRunner {
    enum RunnerError: LocalizedError {
        case ffmpegNotFound
        case failed(code: Int32, details: String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "未找到 ffmpeg。请先安装：brew install ffmpeg"
            case let .failed(code, details):
                return "ffmpeg 执行失败（退出码 \(code)）：\(details)"
            }
        }
    }

    func transcode(
        input: URL,
        output: URL,
        format: ConversionFormat,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        let executable = try resolveFFmpegPath()
        let process = Process()
        process.executableURL = executable

        let arguments = ["-y", "-i", input.path] + format.extraArguments + [output.path]
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else {
                return
            }
            logHandler(message)
        }

        try process.run()
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw RunnerError.failed(code: process.terminationStatus, details: "\(input.lastPathComponent) -> \(output.lastPathComponent)")
        }
    }

    private func resolveFFmpegPath() throws -> URL {
        let fileManager = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        if let match = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: match)
        }

        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for path in envPath.split(separator: ":") {
            let candidate = String(path) + "/ffmpeg"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw RunnerError.ffmpegNotFound
    }
}
