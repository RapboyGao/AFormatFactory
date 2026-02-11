import Foundation

private struct TaskExecutionContext {
    let id: UUID
    let inputURL: URL
    let outputURL: URL
    let format: ConversionFormat
    let overwriteExisting: Bool
    let extraArguments: [String]
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
    func commandText(for task: ConversionTask) -> String {
        let args = FFmpegRunner.commandArguments(
            input: task.inputURL,
            output: task.outputURL,
            format: task.format,
            overwriteExisting: task.overwriteExisting,
            extraArguments: task.extraArguments
        )
        return FFmpegRunner.commandString(arguments: args)
    }

    func removeSelectedTask() {
        guard let selectedTaskID else { return }
        removeTask(id: selectedTaskID)
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
        if selectedTaskID == id {
            selectedTaskID = tasks.indices.contains(index) ? tasks[index].id : tasks.last?.id
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

        let removedSelected = removable.contains { idx in
            tasks[idx].id == selectedTaskID
        }
        tasks.remove(atOffsets: IndexSet(removable))
        if removedSelected {
            selectedTaskID = tasks.first?.id
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
    func addTasksFromSelection() -> Int {
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

        let newTasks = files.map { file -> ConversionTask in
            let output = outputURL(for: file)
            let lines = [
                "任务已创建。",
                "输入：\(file.path)",
                "输出：\(output.path)",
                "格式：\(format.displayName)",
                "参数：\(optionsSummary)"
            ]

            return ConversionTask(
                id: UUID(),
                createdAt: Date(),
                inputURL: file,
                outputURL: output,
                format: format,
                domain: domain,
                overwriteExisting: overwriteExistingFiles,
                extraArguments: extraArguments,
                optionsSummary: optionsSummary,
                status: .queued,
                startedAt: nil,
                finishedAt: nil,
                logs: lines.joined(separator: "\n")
            )
        }

        tasks.append(contentsOf: newTasks)
        switch domain {
        case .video:
            selectedVideoFiles.removeAll()
        case .audio:
            selectedAudioFiles.removeAll()
        }
        if selectedTaskID == nil {
            selectedTaskID = newTasks.first?.id
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
        tasks.removeAll { $0.status == .succeeded || $0.status == .failed }
        if let selectedTaskID, tasks.contains(where: { $0.id == selectedTaskID }) == false {
            self.selectedTaskID = tasks.first?.id
        }
    }

    nonisolated func runTask(id: UUID) async {
        guard let context = await MainActor.run(body: { self.prepareTaskForExecution(id: id) }) else {
            return
        }

        do {
            try await FFmpegRunner().transcode(
                input: context.inputURL,
                output: context.outputURL,
                format: context.format,
                overwriteExisting: context.overwriteExisting,
                extraArguments: context.extraArguments
            ) { [weak self] message in
                Task { @MainActor in
                    self?.appendTaskLog(id: context.id, line: message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            await MainActor.run {
                self.markTaskSucceeded(id: context.id)
            }
        } catch {
            await MainActor.run {
                self.markTaskFailed(id: context.id, reason: error.localizedDescription)
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

        tasks[index].status = .running
        tasks[index].startedAt = Date()
        appendTaskLog(id: id, line: "开始执行任务...")

        return TaskExecutionContext(
            id: id,
            inputURL: tasks[index].inputURL,
            outputURL: tasks[index].outputURL,
            format: tasks[index].format,
            overwriteExisting: tasks[index].overwriteExisting,
            extraArguments: tasks[index].extraArguments
        )
    }

    private func markTaskSucceeded(id: UUID) {
        guard let index = indexOfTask(id: id) else { return }
        tasks[index].status = .succeeded
        tasks[index].finishedAt = Date()
        appendTaskLog(id: id, line: "任务完成。")
    }

    private func markTaskFailed(id: UUID, reason: String) {
        guard let index = indexOfTask(id: id) else { return }
        tasks[index].status = .failed
        tasks[index].finishedAt = Date()
        appendTaskLog(id: id, line: "任务失败：\(reason)")
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

    private func indexOfTask(id: UUID) -> Int? {
        tasks.firstIndex(where: { $0.id == id })
    }
}
