import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers
import AFormatFactoryFFmpegKit

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
            Task { @MainActor in
                await loadMediaEditSourceInfo(from: url)
            }
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

        let chapters = normalizedMediaEditChapters()

        let args = mediaEditArguments(
            inputVideo: input,
            additionalAudio: mediaEditAdditionalAudioURL,
            subtitle: mediaEditSubtitleURL,
            output: outputURL,
            overwrite: mediaEditOverwriteExisting,
            metadata: metadata,
            outputExtension: outputExt,
            hasChapters: !chapters.isEmpty
        )

        mediaEditIsProcessing = true
        appendMediaEditLog("开始处理：\(input.lastPathComponent)")
        appendMediaEditLog(FFmpegEngine.commandString(arguments: args))

        do {
            var extra = args
            if extra.count >= 4 {
                extra.removeFirst(3)
                extra.removeLast()
            }
            let job = FFmpegJob(
                id: UUID(),
                input: input,
                output: outputURL,
                overwriteExisting: mediaEditOverwriteExisting,
                arguments: extra,
                mediaEditConfig: FFmpegMediaEditConfig(
                    additionalAudioInput: mediaEditAdditionalAudioURL,
                    subtitleInput: mediaEditSubtitleURL,
                    subtitleCodec: ["mp4", "mov", "m4v"].contains(outputExt.lowercased()) ? "mov_text" : "copy",
                    metadata: metadata,
                    chapters: chapters.map {
                        FFmpegMediaEditChapter(
                            startMilliseconds: $0.startMS,
                            endMilliseconds: $0.endMS,
                            title: $0.title
                        )
                    }
                )
            )
            _ = try await engine.execute(
                job: job,
                callbacks: FFmpegCallbacks(
                    onLog: { [weak self] _, message in
                        Task { @MainActor in
                            self?.appendMediaEditLog(message.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    },
                    onProgress: { _ in },
                    onState: { _ in }
                )
            )
            appendMediaEditLog("处理完成：\(outputURL.path)")
            appendAppLog("媒体编辑完成：\(outputURL.lastPathComponent)")
        } catch {
            appendMediaEditLog("处理失败：\(error.localizedDescription)")
            appendAppLog("媒体编辑失败：\(error.localizedDescription)")
        }

        mediaEditIsProcessing = false
    }

    private func loadMediaEditSourceInfo(from url: URL) async {
        appendMediaEditLog("正在读取源文件信息...")

        let asset = AVURLAsset(url: url)
        do {
            let metadataItems = try await loadAllMetadataItems(from: asset)
            await applyLoadedMetadata(metadataItems)
            mediaEditChapters = try await loadChapters(from: asset)

            appendMediaEditLog("已自动加载源文件信息：metadata \(metadataItems.count) 项，章节 \(mediaEditChapters.count) 项。")
        } catch {
            appendMediaEditLog("读取源文件信息失败：\(error.localizedDescription)")
        }
    }

    private func mediaEditArguments(
        inputVideo: URL,
        additionalAudio: URL?,
        subtitle: URL?,
        output: URL,
        overwrite: Bool,
        metadata: [String: String],
        outputExtension: String,
        hasChapters: Bool
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
            nextInputIndex += 1
        }
        if hasChapters {
            args += ["-map_chapters", "-1"]
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

    private func loadAllMetadataItems(from asset: AVURLAsset) async throws -> [AVMetadataItem] {
        let formats = try await asset.load(.availableMetadataFormats)
        var result: [AVMetadataItem] = []
        for format in formats {
            let items = try await asset.loadMetadata(for: format)
            result.append(contentsOf: items)
        }
        return result
    }

    private func applyLoadedMetadata(_ items: [AVMetadataItem]) async {
        if let title = await valueFromMetadata(items, commonKey: .commonKeyTitle) {
            mediaEditMetadataTitle = title
        }
        if let artist = await valueFromMetadata(items, commonKey: .commonKeyArtist) {
            mediaEditMetadataArtist = artist
        }
        if let album = await valueFromMetadata(items, commonKey: .commonKeyAlbumName) {
            mediaEditMetadataAlbum = album
        }
        if let comment = await valueFromMetadata(items, commonKey: .commonKeyDescription) {
            mediaEditMetadataComment = comment
        }
        if let creationDate = await valueFromMetadata(items, commonKey: .commonKeyCreationDate) {
            mediaEditMetadataYear = extractYear(from: creationDate)
        }
        if let genre = await valueFromMetadata(items, commonKey: .commonKeyType) {
            mediaEditMetadataGenre = genre
        }
        if let copyright = await valueFromMetadata(items, commonKey: .commonKeyCopyrights) {
            mediaEditMetadataCopyright = copyright
        }
        if let language = firstMetadataLanguage(items) {
            mediaEditMetadataLanguage = language
        }
    }

    private func valueFromMetadata(_ items: [AVMetadataItem], commonKey: AVMetadataKey) async -> String? {
        for item in items {
            guard item.commonKey == commonKey else { continue }
            let stringValue = try? await item.load(.stringValue)
            if let value = nonEmptyValue(stringValue ?? "") {
                return value
            }
        }
        return nil
    }

    private func firstMetadataLanguage(_ items: [AVMetadataItem]) -> String? {
        for item in items {
            if let localeID = item.locale?.identifier, let value = nonEmptyValue(localeID) {
                return value
            }
            if let extTag = item.extendedLanguageTag, let value = nonEmptyValue(extTag) {
                return value
            }
        }
        return nil
    }

    private func extractYear(from raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count >= 4 {
            return String(digits.prefix(4))
        }
        return raw
    }

    private func loadChapters(from asset: AVURLAsset) async throws -> [MediaEditChapter] {
        let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
        var chapters: [MediaEditChapter] = []
        chapters.reserveCapacity(groups.count)

        for (index, group) in groups.enumerated() {
            let start = max(0, CMTimeGetSeconds(group.timeRange.start))
            let end = max(start, CMTimeGetSeconds(group.timeRange.start + group.timeRange.duration))
            let startText = formatMediaEditTime(start)
            let endText = formatMediaEditTime(end)
            let title = await firstChapterTitle(from: group.items) ?? "Chapter \(index + 1)"
            chapters.append(MediaEditChapter(startTime: startText, endTime: endText, title: title))
        }

        return chapters
    }

    private func firstChapterTitle(from items: [AVMetadataItem]) async -> String? {
        for item in items where item.commonKey == .commonKeyTitle {
            let stringValue = try? await item.load(.stringValue)
            if let value = nonEmptyValue(stringValue ?? "") {
                return value
            }
        }
        for item in items {
            let stringValue = try? await item.load(.stringValue)
            if let value = nonEmptyValue(stringValue ?? "") {
                return value
            }
        }
        return nil
    }

    private func formatMediaEditTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        return String(format: "%.3f", clamped)
    }
}
