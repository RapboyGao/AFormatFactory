import AppKit
import Foundation
import ImageIO
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

    func pickImageFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "heic"),
            UTType(filenameExtension: "heif"),
            UTType(filenameExtension: "hif")
        ].compactMap { $0 }

        if panel.runModal() == .OK {
            selectedImageFiles = panel.urls
            selectedImageFileSet = []
            if let first = selectedImageFiles.first {
                setCurrentImage(first)
            }
            appendAppLog("图片查看器：已选择 \(selectedImageFiles.count) 个文件。")
        }
    }

    func setCurrentImage(_ url: URL) {
        currentImageURL = url
        imageViewerZoom = 1
        imageFullscreenZoom = 1
        imageFullscreenOffset = .zero

        currentImage = NSImage(contentsOf: url)
        currentImagePixelSize = imagePixelSize(for: url) ?? .zero
        currentImageFileSizeBytes = fileSize(for: url)
        appendAppLog("图片查看器：已加载 \(url.lastPathComponent)")
    }

    func removeSelectedImageFile(_ url: URL) {
        selectedImageFiles.removeAll { $0 == url }
        selectedImageFileSet.remove(url)
        if currentImageURL == url {
            currentImageURL = nil
            currentImage = nil
            currentImagePixelSize = .zero
            currentImageFileSizeBytes = 0
            imageFullscreenPresented = false
            if let next = selectedImageFiles.first {
                setCurrentImage(next)
            }
        }
    }

    func toggleImageFileSelection(_ url: URL) {
        if selectedImageFileSet.contains(url) {
            selectedImageFileSet.remove(url)
        } else {
            selectedImageFileSet.insert(url)
        }
    }

    func selectAllImageFiles() {
        selectedImageFileSet = Set(selectedImageFiles)
    }

    func clearImageFileSelection() {
        selectedImageFileSet.removeAll()
    }

    func removeSelectedImageFiles() {
        guard !selectedImageFileSet.isEmpty else { return }
        let removing = selectedImageFileSet
        selectedImageFiles.removeAll { removing.contains($0) }
        if let currentImageURL, removing.contains(currentImageURL) {
            self.currentImageURL = nil
            currentImage = nil
            currentImagePixelSize = .zero
            currentImageFileSizeBytes = 0
            if let next = selectedImageFiles.first {
                setCurrentImage(next)
            }
        }
        selectedImageFileSet.removeAll()
        if selectedImageFiles.isEmpty {
            imageFullscreenPresented = false
        }
        appendAppLog("图片查看器：已批量移除图片。")
    }

    func presentImageFullscreen() {
        guard currentImage != nil else { return }
        imageFullscreenZoom = 1
        imageFullscreenOffset = .zero
        imageFullscreenPresented = true
    }

    func dismissImageFullscreen() {
        imageFullscreenPresented = false
        imageSlideshowEnabled = false
    }

    func showNextImage() {
        guard !selectedImageFiles.isEmpty else { return }
        guard let current = currentImageURL, let index = selectedImageFiles.firstIndex(of: current) else {
            if let first = selectedImageFiles.first {
                setCurrentImage(first)
            }
            return
        }
        let nextIndex = selectedImageFiles.index(after: index)
        let resolvedIndex = nextIndex == selectedImageFiles.endIndex ? selectedImageFiles.startIndex : nextIndex
        setCurrentImage(selectedImageFiles[resolvedIndex])
    }

    func showPreviousImage() {
        guard !selectedImageFiles.isEmpty else { return }
        guard let current = currentImageURL, let index = selectedImageFiles.firstIndex(of: current) else {
            if let first = selectedImageFiles.first {
                setCurrentImage(first)
            }
            return
        }
        let resolvedIndex = index == selectedImageFiles.startIndex ? selectedImageFiles.index(before: selectedImageFiles.endIndex) : selectedImageFiles.index(before: index)
        setCurrentImage(selectedImageFiles[resolvedIndex])
    }

    func adjustFullscreenImageZoom(with deltaY: CGFloat) {
        let sensitivity = max(-0.6, min(0.6, Double(deltaY) / 600.0))
        imageFullscreenZoom = min(8.0, max(0.2, imageFullscreenZoom - sensitivity))
    }

    func dragFullscreenImage(by translation: CGSize) {
        imageFullscreenOffset.width += translation.width
        imageFullscreenOffset.height += translation.height
    }

    func exportSelectedImagesAsJPEG() {
        guard !selectedImageFiles.isEmpty else {
            appendAppLog("图片查看器：请先选择至少一张图片。")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentImageURL?.deletingLastPathComponent()

        guard panel.runModal() == .OK, let outputDirectory = panel.url else { return }

        var successCount = 0
        for inputURL in selectedImageFiles {
            let outputURL = outputDirectory
                .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("jpg")

            do {
                try exportImageAsJPEG(inputURL: inputURL, outputURL: outputURL)
                successCount += 1
            } catch {
                appendAppLog("图片查看器：导出失败 \(inputURL.lastPathComponent)，\(error.localizedDescription)")
            }
        }
        appendAppLog("图片查看器：已批量导出 \(successCount)/\(selectedImageFiles.count) 张 JPEG 到 \(outputDirectory.path)")
    }

    private func exportImageAsJPEG(inputURL: URL, outputURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "AFormatFactory.ImageViewer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法读取 HEIC/HIF/HEIF 图像。"
            ])
        }

        try ensureDirectoryExists(at: outputURL.deletingLastPathComponent())
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "AFormatFactory.ImageViewer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "无法创建 JPEG 输出。"
            ])
        }

        let properties = [
            kCGImageDestinationLossyCompressionQuality: 1.0
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "AFormatFactory.ImageViewer", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "JPEG 写入失败。"
            ])
        }
    }

    private func imagePixelSize(for url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
