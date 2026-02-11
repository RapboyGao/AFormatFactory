import AppKit
import AVFoundation
import Foundation

extension ContentViewModel {
    func setPreviewTarget(_ file: URL) {
        previewTargetFile = file
        previewPlayheadSeconds = 0
        isPreviewPlaying = false

        Task { @MainActor in
            await refreshPreviewMetadata(for: file)
            applyParametersToPreview()
            pushPreviewSnapshot()
        }
    }

    func syncPreviewToParameters() {
        guard !isSyncingPreviewState else { return }
        isSyncingPreviewState = true
        defer { isSyncingPreviewState = false }

        if let size = previewVideoSize, size.width > 0, size.height > 0 {
            let rect = previewCropRect.clamped()
            let cropW = max(1, Int((rect.width * size.width).rounded()))
            let cropH = max(1, Int((rect.height * size.height).rounded()))
            let cropX = max(0, Int((rect.x * size.width).rounded()))
            let cropY = max(0, Int((rect.y * size.height).rounded()))

            if rect == .full {
                videoCropWidth = ""
                videoCropHeight = ""
                videoCropX = ""
                videoCropY = ""
            } else {
                videoCropWidth = "\(cropW)"
                videoCropHeight = "\(cropH)"
                videoCropX = "\(cropX)"
                videoCropY = "\(cropY)"
            }
        }

        videoRotate = previewTransformState.rotate
        videoFlipHorizontal = previewTransformState.flipHorizontal
        videoFlipVertical = previewTransformState.flipVertical

        startTime = previewTimeRangeStart > 0 ? String(format: "%.3f", previewTimeRangeStart) : ""

        if let end = previewTimeRangeEnd, end > previewTimeRangeStart {
            duration = String(format: "%.3f", end - previewTimeRangeStart)
        } else {
            duration = ""
        }

        enforceCopyCompatibility()
    }

    func applyParametersToPreview() {
        guard !isSyncingPreviewState else { return }
        isSyncingPreviewState = true
        defer { isSyncingPreviewState = false }

        previewTransformState.rotate = videoRotate
        previewTransformState.flipHorizontal = videoFlipHorizontal
        previewTransformState.flipVertical = videoFlipVertical

        let start = Double(startTime.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        previewTimeRangeStart = max(0, start)

        if let d = Double(duration.trimmingCharacters(in: .whitespacesAndNewlines)), d > 0 {
            previewTimeRangeEnd = previewTimeRangeStart + d
        } else {
            previewTimeRangeEnd = previewDurationSeconds > 0 ? previewDurationSeconds : nil
        }

        if let size = previewVideoSize, size.width > 0, size.height > 0,
           let w = Int(videoCropWidth), let h = Int(videoCropHeight), w > 0, h > 0 {
            let x = Int(videoCropX) ?? 0
            let y = Int(videoCropY) ?? 0
            previewCropRect = NormalizedCropRect(
                x: Double(max(0, x)) / size.width,
                y: Double(max(0, y)) / size.height,
                width: Double(w) / size.width,
                height: Double(h) / size.height
            ).clamped()
        } else {
            previewCropRect = .full
        }

        enforceCopyCompatibility()
    }

    func addFilterNode(_ node: FilterNode) {
        pushPreviewSnapshot()
        var mutable = node
        if mutable.kind.isVideo {
            mutable.order = filterGraph.videoNodes.count
            filterGraph.videoNodes.append(mutable)
        } else {
            mutable.order = filterGraph.audioNodes.count
            filterGraph.audioNodes.append(mutable)
        }
        syncFilterOrders()
        enforceCopyCompatibility()
    }

    func updateFilterNode(_ id: UUID, params: [String: String]) {
        pushPreviewSnapshot()
        if let idx = filterGraph.videoNodes.firstIndex(where: { $0.id == id }) {
            filterGraph.videoNodes[idx].params = params
        } else if let idx = filterGraph.audioNodes.firstIndex(where: { $0.id == id }) {
            filterGraph.audioNodes[idx].params = params
        }
        enforceCopyCompatibility()
    }

    func setFilterNodeEnabled(_ id: UUID, enabled: Bool) {
        if let idx = filterGraph.videoNodes.firstIndex(where: { $0.id == id }) {
            filterGraph.videoNodes[idx].enabled = enabled
        } else if let idx = filterGraph.audioNodes.firstIndex(where: { $0.id == id }) {
            filterGraph.audioNodes[idx].enabled = enabled
        }
        enforceCopyCompatibility()
    }

    func moveFilterNode(from source: IndexSet, to destination: Int, isVideo: Bool) {
        pushPreviewSnapshot()
        if isVideo {
            filterGraph.videoNodes.move(fromOffsets: source, toOffset: destination)
        } else {
            filterGraph.audioNodes.move(fromOffsets: source, toOffset: destination)
        }
        syncFilterOrders()
        enforceCopyCompatibility()
    }

    func removeFilterNode(_ id: UUID) {
        pushPreviewSnapshot()
        filterGraph.videoNodes.removeAll(where: { $0.id == id })
        filterGraph.audioNodes.removeAll(where: { $0.id == id })
        syncFilterOrders()
    }

    func undoPreviewEdit() {
        guard let snapshot = previewUndoStack.popLast() else { return }
        previewRedoStack.append(currentSnapshot())
        apply(snapshot: snapshot)
    }

    func redoPreviewEdit() {
        guard let snapshot = previewRedoStack.popLast() else { return }
        previewUndoStack.append(currentSnapshot())
        apply(snapshot: snapshot)
    }

    func exportCurrentFrame(to url: URL? = nil) {
        guard let source = previewTargetFile else { return }

        let targetURL: URL
        if let url {
            targetURL = url
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "preview-frame.png"
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            targetURL = selected
        }

        Task {
            do {
                let asset = AVURLAsset(url: source)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: max(0, previewPlayheadSeconds), preferredTimescale: 600)
                let imageRef = try generator.copyCGImage(at: time, actualTime: nil)
                let rep = NSBitmapImageRep(cgImage: imageRef)
                guard let data = rep.representation(using: .png, properties: [:]) else { return }
                try data.write(to: targetURL, options: .atomic)
                await MainActor.run {
                    appendAppLog("预览截图已导出：\(targetURL.path)")
                }
            } catch {
                await MainActor.run {
                    appendAppLog("导出预览截图失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func pushPreviewSnapshot() {
        previewUndoStack.append(currentSnapshot())
        if previewUndoStack.count > 50 {
            previewUndoStack.removeFirst(previewUndoStack.count - 50)
        }
        previewRedoStack.removeAll()
    }

    func refreshPreviewTargetIfNeeded() {
        guard previewTargetFile == nil else { return }
        if let first = selectedFiles.first {
            setPreviewTarget(first)
        }
    }

    private func currentSnapshot() -> PreviewSnapshot {
        PreviewSnapshot(
            cropRect: previewCropRect,
            transform: previewTransformState,
            timeRangeStart: previewTimeRangeStart,
            timeRangeEnd: previewTimeRangeEnd,
            filterGraph: filterGraph,
            editorMode: editorMode
        )
    }

    private func apply(snapshot: PreviewSnapshot) {
        previewCropRect = snapshot.cropRect
        previewTransformState = snapshot.transform
        previewTimeRangeStart = snapshot.timeRangeStart
        previewTimeRangeEnd = snapshot.timeRangeEnd
        filterGraph = snapshot.filterGraph
        editorMode = snapshot.editorMode
        syncPreviewToParameters()
    }

    private func syncFilterOrders() {
        for i in filterGraph.videoNodes.indices {
            filterGraph.videoNodes[i].order = i
        }
        for i in filterGraph.audioNodes.indices {
            filterGraph.audioNodes[i].order = i
        }
    }

    private func refreshPreviewMetadata(for file: URL) async {
        let asset = AVURLAsset(url: file)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            previewDurationSeconds = seconds.isFinite ? max(0, seconds) : 0
            if previewTimeRangeEnd == nil {
                previewTimeRangeEnd = previewDurationSeconds > 0 ? previewDurationSeconds : nil
            }
        } catch {
            previewDurationSeconds = 0
            previewTimeRangeEnd = nil
        }

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                previewVideoSize = CGSize(width: abs(size.width), height: abs(size.height))
            } else {
                previewVideoSize = nil
            }
        } catch {
            previewVideoSize = nil
        }
    }

    func enforceCopyCompatibility() {
        let hasTrim: Bool = {
            if previewTimeRangeStart > 0.001 { return true }
            guard let end = previewTimeRangeEnd, previewDurationSeconds > 0 else { return false }
            return abs(end - previewDurationSeconds) > 0.001
        }()

        let hasVideoVisualEdit = previewCropRect != .full
            || previewTransformState.rotate != .none
            || previewTransformState.flipHorizontal
            || previewTransformState.flipVertical
            || !filterGraph.videoNodes.filter(\.enabled).isEmpty
            || hasTrim

        let hasAudioVisualEdit = !filterGraph.audioNodes.filter(\.enabled).isEmpty
            || enableLoudnorm
            || !(audioVolumeDB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        var changed = false
        if hasVideoVisualEdit, copyVideoStream {
            copyVideoStream = false
            changed = true
        }
        if hasAudioVisualEdit, copyAudioStream {
            copyAudioStream = false
            changed = true
        }
        if changed {
            showCopyDisabledHint = true
            appendAppLog("已启用可视编辑，自动关闭 Copy。")
        }
    }
}
