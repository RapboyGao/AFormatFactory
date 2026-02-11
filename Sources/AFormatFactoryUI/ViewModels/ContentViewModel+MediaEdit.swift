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

    func addMediaEditChapter() {
        let index = mediaEditChapters.count + 1
        let suggestedStart: String
        if let last = mediaEditChapters.last {
            suggestedStart = last.endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : last.endTime
        } else {
            suggestedStart = "0"
        }
        mediaEditChapters.append(
            MediaEditChapter(
                startTime: suggestedStart,
                endTime: "60",
                title: "Chapter \(index)"
            )
        )
    }

    func removeMediaEditChapter(_ chapterID: UUID) {
        mediaEditChapters.removeAll { $0.id == chapterID }
    }

    func clearMediaEditChapters() {
        mediaEditChapters.removeAll()
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

        var temporaryChapterMetadataURL: URL?
        let chapters = normalizedMediaEditChapters()
        if !chapters.isEmpty {
            do {
                temporaryChapterMetadataURL = try makeChapterMetadataFile(chapters: chapters)
            } catch {
                appendMediaEditLog("章节写入失败：\(error.localizedDescription)")
                appendAppLog("章节写入失败：\(error.localizedDescription)")
                return
            }
        }

        defer {
            if let temporaryChapterMetadataURL {
                try? FileManager.default.removeItem(at: temporaryChapterMetadataURL)
            }
        }

        let args = mediaEditArguments(
            inputVideo: input,
            additionalAudio: mediaEditAdditionalAudioURL,
            subtitle: mediaEditSubtitleURL,
            chapterMetadataInput: temporaryChapterMetadataURL,
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
        chapterMetadataInput: URL?,
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
        if let chapterMetadataInput {
            args += ["-f", "ffmetadata", "-i", chapterMetadataInput.path]
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
            nextInputIndex += 1
        }
        if chapterMetadataInput != nil {
            args += ["-map_chapters", "\(nextInputIndex)"]
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

    private func normalizedMediaEditChapters() -> [(startMS: Int, endMS: Int, title: String)] {
        var result: [(startMS: Int, endMS: Int, title: String)] = []
        for (index, chapter) in mediaEditChapters.enumerated() {
            guard
                let startSeconds = parseMediaEditTimeSeconds(chapter.startTime),
                let endSeconds = parseMediaEditTimeSeconds(chapter.endTime)
            else {
                appendMediaEditLog("跳过第 \(index + 1) 个章节：时间格式无效。")
                continue
            }

            let startMS = Int((startSeconds * 1000).rounded())
            let endMS = Int((endSeconds * 1000).rounded())
            guard endMS > startMS else {
                appendMediaEditLog("跳过第 \(index + 1) 个章节：结束时间必须大于开始时间。")
                continue
            }

            let title = nonEmptyValue(chapter.title) ?? "Chapter \(index + 1)"
            result.append((startMS: startMS, endMS: endMS, title: title))
        }
        return result.sorted(by: { $0.startMS < $1.startMS })
    }

    private func makeChapterMetadataFile(chapters: [(startMS: Int, endMS: Int, title: String)]) throws -> URL {
        let fileName = "aformatfactory-chapters-\(UUID().uuidString).ffmeta"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)

        var lines: [String] = [";FFMETADATA1"]
        for chapter in chapters {
            lines += [
                "[CHAPTER]",
                "TIMEBASE=1/1000",
                "START=\(chapter.startMS)",
                "END=\(chapter.endMS)",
                "title=\(escapeFFMetadataValue(chapter.title))"
            ]
        }

        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func escapeFFMetadataValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "=", with: "\\=")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseMediaEditTimeSeconds(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = Double(trimmed), direct >= 0 {
            return direct
        }

        let segments = trimmed.split(separator: ":")
        guard !segments.isEmpty, segments.count <= 3 else { return nil }
        var values: [Double] = []
        for segment in segments {
            guard let number = Double(segment), number >= 0 else { return nil }
            values.append(number)
        }

        switch values.count {
        case 1:
            return values[0]
        case 2:
            return values[0] * 60 + values[1]
        case 3:
            return values[0] * 3600 + values[1] * 60 + values[2]
        default:
            return nil
        }
    }
}
