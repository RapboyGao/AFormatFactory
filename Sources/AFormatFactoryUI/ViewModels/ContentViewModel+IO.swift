import AppKit
import Foundation
import UniformTypeIdentifiers

extension ContentViewModel {
    func ensureDirectoryExists(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
            if let first = selectedFiles.first {
                setPreviewTarget(first)
            }
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let directory = panel.url {
            outputDirectory = directory
            try? ensureDirectoryExists(at: directory)
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
        if previewTargetFile == file {
            previewTargetFile = nil
            refreshPreviewTargetIfNeeded()
        }
        appendAppLog("已移除输入文件：\(file.lastPathComponent)")
    }

    func outputURL(for file: URL) -> URL {
        let directory = resolvedOutputDirectory(for: file)
        let baseName = file.deletingPathExtension().lastPathComponent
        let ext = format.outputExtension
        var filename = "\(baseName).\(ext)"

        let sourceDirMode = outputLocationMode == .sourceDirectory
        if sourceDirMode, file.pathExtension.lowercased() == ext.lowercased() {
            filename = "\(baseName)_converted.\(ext)"
        }

        return directory.appendingPathComponent(filename, isDirectory: false)
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

    private func resolvedOutputDirectory(for file: URL) -> URL {
        switch outputLocationMode {
        case .sourceDirectory:
            return file.deletingLastPathComponent()
        case .specifiedDirectory:
            return outputDirectory ?? file.deletingLastPathComponent()
        }
    }
}
