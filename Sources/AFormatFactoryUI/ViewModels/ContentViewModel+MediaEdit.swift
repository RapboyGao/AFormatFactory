import AppKit
import Foundation
import UniformTypeIdentifiers

extension ContentViewModel {
    var canRunMediaEdit: Bool {
        mediaEditInputVideoURL != nil && !mediaEditIsProcessing
    }

    var mediaEditResolvedOutputDirectory: URL? {
        switch mediaEditOutputLocationMode {
        case .sourceDirectory:
            return mediaEditInputVideoURL?.deletingLastPathComponent()
        case .specifiedDirectory:
            return mediaEditOutputDirectory
        }
    }

    func pickMediaEditVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            "mp4", "mov", "mkv", "m4v", "avi", "wmv", "flv", "webm",
            "mpeg", "mpg", "ts", "m2ts", "mts", "vob", "ogv", "3gp"
        ].compactMap { UTType(filenameExtension: $0) }

        if panel.runModal() == .OK, let url = panel.url {
            mediaEditInputVideoURL = url
            if mediaEditOutputLocationMode == .specifiedDirectory, mediaEditOutputDirectory == nil {
                mediaEditOutputDirectory = url.deletingLastPathComponent()
            }
            appendMediaEditLog("已选择视频：\(url.path)")
        }
    }

    func clearMediaEditVideo() {
        mediaEditInputVideoURL = nil
        mediaEditAdditionalAudioURL = nil
        mediaEditSubtitleURL = nil
    }

    func pickMediaEditOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let directory = panel.url {
            mediaEditOutputLocationMode = .specifiedDirectory
            mediaEditOutputDirectory = directory
            appendMediaEditLog("输出目录：\(directory.path)")
        }
    }

    func pickMediaEditAdditionalAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            "mp3", "wav", "m4a", "aac", "flac", "ogg", "opus", "aif", "aiff", "caf", "wma", "ac3", "mka"
        ].compactMap { UTType(filenameExtension: $0) }

        if panel.runModal() == .OK, let url = panel.url {
            mediaEditAdditionalAudioURL = url
            appendMediaEditLog("附加音频：\(url.path)")
        }
    }

    func pickMediaEditSubtitle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["srt", "ass", "ssa", "vtt"].compactMap { UTType(filenameExtension: $0) }

        if panel.runModal() == .OK, let url = panel.url {
            mediaEditSubtitleURL = url
            appendMediaEditLog("附加字幕：\(url.path)")
        }
    }

    func clearMediaEditAdditionalAudio() {
        mediaEditAdditionalAudioURL = nil
    }

    func clearMediaEditSubtitle() {
        mediaEditSubtitleURL = nil
    }

    func runMediaEdit() async {
        guard !mediaEditIsProcessing else { return }
        guard let input = mediaEditInputVideoURL else {
            appendMediaEditLog("请先选择一个视频文件。")
            return
        }

        let outputDir = mediaEditResolvedOutputDirectory ?? input.deletingLastPathComponent()
        let outputExt = mediaEditOutputFormat.resolvedExtension(source: input)
        let outputName = input.deletingPathExtension().lastPathComponent + "_edited." + outputExt
        let outputURL = outputDir.appendingPathComponent(outputName, isDirectory: false)

        var metadata: [String: String] = [:]
        if let title = nonEmptyValue(mediaEditMetadataTitle) { metadata["title"] = title }
        if let artist = nonEmptyValue(mediaEditMetadataArtist) { metadata["artist"] = artist }
        if let album = nonEmptyValue(mediaEditMetadataAlbum) { metadata["album"] = album }
        if let comment = nonEmptyValue(mediaEditMetadataComment) { metadata["comment"] = comment }
        if let year = nonEmptyValue(mediaEditMetadataYear) { metadata["date"] = year }
        if let genre = nonEmptyValue(mediaEditMetadataGenre) { metadata["genre"] = genre }
        if let copyright = nonEmptyValue(mediaEditMetadataCopyright) { metadata["copyright"] = copyright }
        if let language = nonEmptyValue(mediaEditMetadataLanguage) { metadata["language"] = language }

        let args = mediaEditArguments(
            inputVideo: input,
            additionalAudio: mediaEditAdditionalAudioURL,
            subtitle: mediaEditSubtitleURL,
            output: outputURL,
            overwrite: mediaEditOverwriteExisting,
            metadata: metadata,
            outputExtension: outputExt
        )

        mediaEditIsProcessing = true
        appendMediaEditLog("开始处理：\(input.lastPathComponent)")
        appendMediaEditLog(FFmpegRunner.commandString(arguments: args))

        do {
            try await runner.runCustom(arguments: args) { [weak self] message in
                Task { @MainActor in
                    self?.appendMediaEditLog(message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            appendMediaEditLog("处理完成：\(outputURL.path)")
            appendAppLog("媒体编辑完成：\(outputURL.lastPathComponent)")
        } catch {
            appendMediaEditLog("处理失败：\(error.localizedDescription)")
            appendAppLog("媒体编辑失败：\(error.localizedDescription)")
        }

        mediaEditIsProcessing = false
    }

    private func mediaEditArguments(
        inputVideo: URL,
        additionalAudio: URL?,
        subtitle: URL?,
        output: URL,
        overwrite: Bool,
        metadata: [String: String],
        outputExtension: String
    ) -> [String] {
        var args: [String] = [overwrite ? "-y" : "-n", "-i", inputVideo.path]

        if let additionalAudio {
            args += ["-i", additionalAudio.path]
        }
        if let subtitle {
            args += ["-i", subtitle.path]
        }

        args += ["-map", "0:v:0?"]
        args += ["-map", "0:a?"]
        args += ["-map", "0:s?"]

        var nextInputIndex = 1
        if additionalAudio != nil {
            args += ["-map", "\(nextInputIndex):a?"]
            nextInputIndex += 1
        }
        if subtitle != nil {
            args += ["-map", "\(nextInputIndex):s?"]
        }

        args += ["-c:v", "copy", "-c:a", "copy"]

        let subtitleCodec = ["mp4", "mov", "m4v"].contains(outputExtension.lowercased()) ? "mov_text" : "copy"
        args += ["-c:s", subtitleCodec]

        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            args += ["-metadata", "\(key)=\(value)"]
        }

        args += [output.path]
        return args
    }

    private func appendMediaEditLog(_ line: String) {
        guard !line.isEmpty else { return }
        if mediaEditLogs.isEmpty {
            mediaEditLogs = line
        } else {
            mediaEditLogs += "\n\(line)"
        }
    }

    private func nonEmptyValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
