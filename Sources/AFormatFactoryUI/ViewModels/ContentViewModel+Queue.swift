import AVFoundation
import Foundation
import AFormatFactoryFFmpegKit

private struct TaskExecutionContext {
    let id: UUID
    let inputURL: URL
    let outputURL: URL
    let format: ConversionFormat
    let overwriteExisting: Bool
    let extraArguments: [String]
    let sourceDurationSeconds: Double?
    let estimatedTotalFrames: Double?
}

actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        count = max(1, value)
    }

    func acquire() async {
        if count > 0 {
            count -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let continuation = waiters.removeFirst()
            continuation.resume()
            return
        }
        count += 1
    }
}

extension ContentViewModel {
    private static var runningJobs: Set<UUID> = []
    private static var cancellationRequests: Set<UUID> = []

    func commandText(for task: ConversionTask) -> String {
        let args = FFmpegEngine.commandArguments(
            input: task.inputURL,
            output: task.outputURL,
            overwriteExisting: task.overwriteExisting,
            extraArguments: task.format.extraArguments + task.extraArguments
        )
        return FFmpegEngine.commandString(arguments: args)
    }

    func terminateSelectedTask() {
        for id in selectedTaskIDs {
            terminateTask(id: id)
        }
    }

    func terminateTask(id: UUID) {
        guard let index = indexOfTask(id: id) else { return }

        switch tasks[index].status {
        case .queued:
            markTaskCancelled(id: id, reason: "任务在排队阶段被终止。")
            appendAppLog("已终止排队任务：\(tasks[index].inputURL.lastPathComponent)")
        case .running:
            Self.cancellationRequests.insert(id)
            if Self.runningJobs.contains(id) {
                engine.cancel(jobID: id)
                appendAppLog("已请求终止运行任务：\(tasks[index].inputURL.lastPathComponent)")
            }
        default:
            break
        }
    }

    func removeSelectedTask() {
        guard !selectedTaskIDs.isEmpty else { return }
        let selected = selectedTaskIDs
        let indices = tasks.indices.filter { selected.contains(tasks[$0].id) }.sorted(by: >)
        for index in indices {
            removeTask(id: tasks[index].id)
        }
    }

    func removeTask(id: UUID) {
        guard !isProcessingQueue else {
            appendAppLog("队列执行中，暂不允许删除任务。")
            return
        }
        guard let index = indexOfTask(id: id) else { return }

        let task = tasks[index]
        guard task.status != .running else {
            appendAppLog("任务正在执行中，不能删除：\(task.inputURL.lastPathComponent)")
            return
        }

        tasks.remove(at: index)
        selectedTaskIDs.remove(id)
        if selectedTaskIDs.isEmpty, let firstID = tasks.first?.id {
            selectedTaskIDs = [firstID]
        }
        appendAppLog("已删除任务：\(task.inputURL.lastPathComponent)")
    }

    func removeTasks(at offsets: IndexSet) {
        guard !isProcessingQueue else {
            appendAppLog("队列执行中，暂不允许删除任务。")
            return
        }

        let runningOffsets = offsets.filter { idx in
            tasks.indices.contains(idx) && tasks[idx].status == .running
        }
        if !runningOffsets.isEmpty {
            appendAppLog("包含执行中任务，已跳过这些删除项。")
        }

        let removable = offsets.filter { idx in
            tasks.indices.contains(idx) && tasks[idx].status != .running
        }
        guard !removable.isEmpty else { return }

        let removedIDs = removable.compactMap { idx in
            tasks.indices.contains(idx) ? tasks[idx].id : nil
        }
        tasks.remove(atOffsets: IndexSet(removable))
        selectedTaskIDs.subtract(removedIDs)
        if selectedTaskIDs.isEmpty, let firstID = tasks.first?.id {
            selectedTaskIDs = [firstID]
        }
        appendAppLog("已删除 \(removable.count) 个任务。")
    }

    func moveTasks(from source: IndexSet, to destination: Int) {
        guard !isProcessingQueue else {
            appendAppLog("队列执行中，暂不允许调整任务顺序。")
            return
        }
        tasks.move(fromOffsets: source, toOffset: destination)
        appendAppLog("任务顺序已更新。")
    }

    @discardableResult
    func addTasksFromSelection() async -> Int {
        syncPreviewToParameters()
        let files = selectedFiles
        guard !files.isEmpty else {
            appendAppLog("请先选择输入文件。")
            return 0
        }

        guard outputLocationMode == .sourceDirectory || outputDirectory != nil else {
            appendAppLog("请先选择输出目录。")
            return 0
        }

        let extraArguments = extraFFmpegArguments()
        let optionsSummary = currentOptionsSummary()

        var newTasks: [ConversionTask] = []
        newTasks.reserveCapacity(files.count)
        for file in files {
            let output = outputURL(for: file)
            do {
                try ensureDirectoryExists(at: output.deletingLastPathComponent())
            } catch {
                appendAppLog("无法创建输出目录：\(output.deletingLastPathComponent().path)，\(error.localizedDescription)")
                continue
            }
            let sourceDuration = await mediaDurationSeconds(for: file)
            let totalFrames = await estimatedFrameCount(for: file, duration: sourceDuration)
            let task = ConversionTask(
                id: UUID(),
                createdAt: Date(),
                inputURL: file,
                outputURL: output,
                format: format,
                domain: domain,
                overwriteExisting: overwriteExistingFiles,
                extraArguments: extraArguments,
                optionsSummary: optionsSummary,
                sourceDurationSeconds: sourceDuration,
                estimatedTotalFrames: totalFrames,
                status: .queued,
                startedAt: nil,
                finishedAt: nil,
                logs: "",
                progress: 0,
                processedFrames: nil,
                processedTimeSeconds: nil,
                bitrateKbps: nil,
                speed: nil
            )
            newTasks.append(task)
        }

        guard !newTasks.isEmpty else {
            appendAppLog("未能创建任务：输出目录不可用。")
            return 0
        }

        tasks.append(contentsOf: newTasks)
        switch domain {
        case .video:
            selectedVideoFiles.removeAll()
        case .audio:
            selectedAudioFiles.removeAll()
        }
        if selectedTaskIDs.isEmpty, let firstID = newTasks.first?.id {
            selectedTaskIDs = [firstID]
        }
        appendAppLog("已添加 \(newTasks.count) 个任务到队列。")
        return newTasks.count
    }

    func startQueuedTasks() async {
        guard !isProcessingQueue else {
            appendAppLog("任务队列正在执行中。")
            return
        }

        let queuedTaskIDs = tasks.filter { $0.status == .queued }.map(\.id)
        guard !queuedTaskIDs.isEmpty else {
            appendAppLog("没有待执行任务。")
            return
        }

        isProcessingQueue = true
        appendAppLog("开始执行 \(queuedTaskIDs.count) 个任务，并发数：\(maxConcurrentTasks)")

        let semaphore = AsyncSemaphore(value: maxConcurrentTasks)
        await withTaskGroup(of: Void.self) { group in
            for id in queuedTaskIDs {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await semaphore.acquire()
                    await self.runTask(id: id)
                    await semaphore.release()
                }
            }
            await group.waitForAll()
        }

        isProcessingQueue = false
        appendAppLog("队列执行完成。")
    }

    func clearFinishedTasks() {
        tasks.removeAll { $0.status == .succeeded || $0.status == .failed || $0.status == .cancelled }
        selectedTaskIDs = selectedTaskIDs.filter { id in
            tasks.contains(where: { $0.id == id })
        }
        if selectedTaskIDs.isEmpty, let firstID = tasks.first?.id {
            selectedTaskIDs = [firstID]
        }
    }

    func shutdownAndCleanup() {
        if let mediaEditActiveJobID {
            engine.cancel(jobID: mediaEditActiveJobID)
        }

        for id in Self.runningJobs {
            engine.cancel(jobID: id)
        }

        for index in tasks.indices {
            if tasks[index].status == .running || tasks[index].status == .queued {
                tasks[index].status = .cancelled
                tasks[index].finishedAt = Date()
            }
        }

        let unfinishedOutputURLs = tasks
            .filter { $0.status != .succeeded }
            .map(\.outputURL)

        for outputURL in unfinishedOutputURLs {
            guard FileManager.default.fileExists(atPath: outputURL.path) else { continue }
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                appendAppLog("退出清理失败：\(outputURL.lastPathComponent)，\(error.localizedDescription)")
            }
        }

        Self.runningJobs.removeAll()
        Self.cancellationRequests.removeAll()
    }

    nonisolated func runTask(id: UUID) async {
        guard let context = await MainActor.run(body: { self.prepareTaskForExecution(id: id) }) else {
            return
        }

        do {
            let job = FFmpegJob(
                id: context.id,
                input: context.inputURL,
                output: context.outputURL,
                overwriteExisting: context.overwriteExisting,
                arguments: context.format.extraArguments + context.extraArguments,
                estimatedDurationSeconds: context.sourceDurationSeconds,
                estimatedTotalFrames: context.estimatedTotalFrames
            )
            _ = try await engine.execute(
                job: job,
                callbacks: FFmpegCallbacks(
                    onLog: { level, message in
                        Task { @MainActor in
                            guard level == .error else { return }
                            self.appendTaskLog(id: context.id, line: message.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    },
                    onProgress: { progress in
                        Task { @MainActor in
                            self.updateTaskProgress(id: context.id, with: progress)
                        }
                    },
                    onState: { state in
                        Task { @MainActor in
                            self.handleTaskStateTransition(id: context.id, state: state)
                        }
                    }
                )
            )
        } catch {
            await MainActor.run {
                if self.isCancellationRequested(id: context.id) {
                    self.markTaskCancelled(id: context.id, reason: "任务已终止。")
                } else {
                    self.markTaskFailed(id: context.id, reason: error.localizedDescription)
                }
            }
        }
    }

    func appendAppLog(_ line: String) {
        guard !line.isEmpty else { return }
        if appLogs.isEmpty {
            appLogs = line
        } else {
            appLogs += "\n\(line)"
        }
    }

    private func prepareTaskForExecution(id: UUID) -> TaskExecutionContext? {
        guard let index = indexOfTask(id: id) else { return nil }
        guard tasks[index].status == .queued else { return nil }

        Self.cancellationRequests.remove(id)
        tasks[index].status = .running
        tasks[index].startedAt = Date()
        tasks[index].progress = 0
        tasks[index].processedFrames = nil
        tasks[index].processedTimeSeconds = nil
        tasks[index].bitrateKbps = nil
        tasks[index].speed = nil

        return TaskExecutionContext(
            id: id,
            inputURL: tasks[index].inputURL,
            outputURL: tasks[index].outputURL,
            format: tasks[index].format,
            overwriteExisting: tasks[index].overwriteExisting,
            extraArguments: tasks[index].extraArguments,
            sourceDurationSeconds: tasks[index].sourceDurationSeconds,
            estimatedTotalFrames: tasks[index].estimatedTotalFrames
        )
    }

    private func markTaskSucceeded(id: UUID) {
        guard let index = indexOfTask(id: id) else { return }
        Self.cancellationRequests.remove(id)
        tasks[index].status = .succeeded
        tasks[index].finishedAt = Date()
        tasks[index].progress = 1
    }

    private func markTaskFailed(id: UUID, reason: String) {
        guard let index = indexOfTask(id: id) else { return }
        Self.cancellationRequests.remove(id)
        tasks[index].status = .failed
        tasks[index].finishedAt = Date()
        appendTaskLog(id: id, line: "任务失败：\(reason)")
    }

    private func markTaskCancelled(id: UUID, reason _: String) {
        guard let index = indexOfTask(id: id) else { return }
        Self.cancellationRequests.remove(id)
        Self.runningJobs.remove(id)
        tasks[index].status = .cancelled
        tasks[index].finishedAt = Date()
    }

    private func appendTaskLog(id: UUID, line: String) {
        guard !line.isEmpty else { return }
        guard let index = indexOfTask(id: id) else { return }

        if tasks[index].logs.isEmpty {
            tasks[index].logs = line
        } else {
            tasks[index].logs += "\n\(line)"
        }
    }

    private func updateTaskProgress(id: UUID, with progress: FFmpegProgress) {
        guard let index = indexOfTask(id: id) else { return }
        guard tasks[index].status == .running else { return }
        if let processedFrames = progress.processedFrames, processedFrames > 0 {
            tasks[index].processedFrames = processedFrames
        }
        if let processedTimeSeconds = progress.processedTimeSeconds, processedTimeSeconds >= 0 {
            tasks[index].processedTimeSeconds = processedTimeSeconds
        }
        if let bitrateKbps = progress.bitrateKbps, bitrateKbps >= 0 {
            tasks[index].bitrateKbps = bitrateKbps
        }
        if let speed = progress.speed, speed >= 0 {
            tasks[index].speed = speed
        }
        guard let ratio = progress.estimatedRatio else { return }
        if ratio > tasks[index].progress {
            tasks[index].progress = max(0, min(1, ratio))
        }
    }

    private func mediaDurationSeconds(for file: URL) async -> Double? {
        let asset = AVURLAsset(url: file)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        } catch {
            return nil
        }
    }

    private func estimatedFrameCount(for file: URL, duration: Double?) async -> Double? {
        guard let duration, duration > 0 else { return nil }
        let asset = AVURLAsset(url: file)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let fpsValue = try await track.load(.nominalFrameRate)
            let fps = Double(fpsValue)
            guard fps.isFinite, fps > 0 else { return nil }
            return duration * fps
        } catch {
            return nil
        }
    }

    private func indexOfTask(id: UUID) -> Int? {
        tasks.firstIndex(where: { $0.id == id })
    }

    private func registerRunningJob(for id: UUID) {
        Self.runningJobs.insert(id)
        if Self.cancellationRequests.contains(id) {
            engine.cancel(jobID: id)
        }
    }

    private func unregisterRunningJob(for id: UUID) {
        Self.runningJobs.remove(id)
    }

    private func isCancellationRequested(id: UUID) -> Bool {
        Self.cancellationRequests.contains(id)
    }

    private func handleTaskStateTransition(id: UUID, state: FFmpegExecutionState) {
        switch state {
        case .started:
            registerRunningJob(for: id)
        case .completed:
            unregisterRunningJob(for: id)
            if isCancellationRequested(id: id) {
                markTaskCancelled(id: id, reason: "任务已终止。")
            } else {
                markTaskSucceeded(id: id)
            }
        case let .failed(reason):
            unregisterRunningJob(for: id)
            if isCancellationRequested(id: id) {
                markTaskCancelled(id: id, reason: "任务已终止。")
            } else {
                markTaskFailed(id: id, reason: reason)
            }
        case .cancelled:
            unregisterRunningJob(for: id)
            markTaskCancelled(id: id, reason: "任务已终止。")
        }
    }
}
