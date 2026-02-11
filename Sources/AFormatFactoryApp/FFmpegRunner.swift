import Foundation

struct FFmpegRunner {
    enum RunnerError: LocalizedError {
        case ffmpegDownloadFailed(reason: String)
        case failed(code: Int32, details: String)

        var errorDescription: String? {
            switch self {
            case let .ffmpegDownloadFailed(reason):
                return "ffmpeg 下载或安装失败：\(reason)"
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
        let executable = try await ensureBundledFFmpeg(logHandler: logHandler)
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

    private func ensureBundledFFmpeg(logHandler: @escaping @Sendable (String) -> Void) async throws -> URL {
        let ffmpegURL = bundledFFmpegURL()
        let fileManager = FileManager.default

        if fileManager.isExecutableFile(atPath: ffmpegURL.path) {
            return ffmpegURL
        }

        let binDirectory = ffmpegURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        } catch {
            throw RunnerError.ffmpegDownloadFailed(reason: "无法创建目录：\(binDirectory.path)")
        }

        logHandler("应用内 ffmpeg 不存在，开始自动下载...")
        let temporaryZip = fileManager.temporaryDirectory.appendingPathComponent("aformatfactory-ffmpeg.zip", isDirectory: false)

        do {
            let downloadURL = try ffmpegDownloadURL()
            let (downloadedURL, response) = try await URLSession.shared.download(from: downloadURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw RunnerError.ffmpegDownloadFailed(reason: "下载返回 HTTP \(http.statusCode)")
            }

            if fileManager.fileExists(atPath: temporaryZip.path) {
                try fileManager.removeItem(at: temporaryZip)
            }
            try fileManager.moveItem(at: downloadedURL, to: temporaryZip)

            try unzip(archive: temporaryZip, to: binDirectory)
            try fileManager.removeItem(at: temporaryZip)

            if fileManager.isExecutableFile(atPath: ffmpegURL.path) == false {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegURL.path)
            }
            logHandler("ffmpeg 下载完成：\(ffmpegURL.path)")
            return ffmpegURL
        } catch let error as RunnerError {
            throw error
        } catch {
            throw RunnerError.ffmpegDownloadFailed(reason: error.localizedDescription)
        }
    }

    private func bundledFFmpegURL() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.appendingPathComponent("Contents/Resources/bin/ffmpeg", isDirectory: false)
        }
        // `swift run` fallback: keep a local binary in the project directory.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent("app/bin/ffmpeg", isDirectory: false)
    }

    private func unzip(archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archive.path, "-d", destination.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unzip error"
            throw RunnerError.ffmpegDownloadFailed(reason: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func ffmpegDownloadURL() throws -> URL {
        #if arch(arm64)
            let raw = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
        #elseif arch(x86_64)
            let raw = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffmpeg.zip"
        #else
            throw RunnerError.ffmpegDownloadFailed(reason: "当前 CPU 架构不支持自动下载 ffmpeg")
        #endif

        guard let url = URL(string: raw) else {
            throw RunnerError.ffmpegDownloadFailed(reason: "ffmpeg 下载地址无效")
        }
        return url
    }
}
