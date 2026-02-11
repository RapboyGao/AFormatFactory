import AppKit
import Foundation

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedFiles: [URL] = []
    @Published var outputDirectory: URL?
    @Published var format: ConversionFormat = .mp4
    @Published var isConverting = false
    @Published var logs = ""

    private let runner = FFmpegRunner()

    func pickInputFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []

        if panel.runModal() == .OK {
            selectedFiles = panel.urls
            appendLog("已选择 \(selectedFiles.count) 个文件。")
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
        guard !selectedFiles.isEmpty else {
            appendLog("请先选择输入文件。")
            return
        }

        guard let outputDirectory else {
            appendLog("请先选择输出目录。")
            return
        }

        isConverting = true
        defer { isConverting = false }

        for (index, file) in selectedFiles.enumerated() {
            let output = outputURL(for: file, in: outputDirectory)
            appendLog("[\(index + 1)/\(selectedFiles.count)] 开始：\(file.lastPathComponent)")

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
