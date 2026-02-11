import AppKit
import Foundation
import UniformTypeIdentifiers

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

    private let runner = FFmpegRunner()

    var selectedFiles: [URL] {
        domain == .video ? selectedVideoFiles : selectedAudioFiles
    }

    var availableFormats: [ConversionFormat] {
        ConversionFormat.formats(for: domain)
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
                try await runner.transcode(input: file, output: output, format: format) { [weak self] message in
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
}
