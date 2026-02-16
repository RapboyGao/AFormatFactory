import AVFoundation
import AFormatFactoryFFmpegC
import Foundation

public enum FFmpegEngineError: LocalizedError {
    case failed(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .failed(reason):
            return reason
        }
    }
}

private final class CallbackBox {
    let callbacks: FFmpegCallbacks

    init(callbacks: FFmpegCallbacks) {
        self.callbacks = callbacks
    }
}

public final class FFmpegEngine: FFmpegEngineProtocol, @unchecked Sendable {
    private static var runningJobs: [UUID: OpaquePointer] = [:]
    private static let runningJobsQueue = DispatchQueue(label: "AFormatFactory.FFmpegEngine.runningJobs")

    public init() {}

    public func probe(url: URL) async throws -> FFmpegMediaInfo {
        try await Task.detached(priority: .userInitiated) {
            var jsonPtr: UnsafeMutablePointer<CChar>?
            let code = aff_probe_media(url.path, &jsonPtr)
            guard code == 0 else {
                throw FFmpegEngineError.failed(reason: Self.lastError())
            }
            defer {
                if let jsonPtr {
                    aff_free_string(jsonPtr)
                }
            }

            guard let jsonPtr else {
                return FFmpegMediaInfo(durationSeconds: nil, streamCount: 0)
            }
            let data = Data(String(cString: jsonPtr).utf8)
            if
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let streams = object["streams"] as? Int
            {
                return FFmpegMediaInfo(durationSeconds: object["duration"] as? Double, streamCount: streams)
            }
            return FFmpegMediaInfo(durationSeconds: nil, streamCount: 0)
        }.value
    }

    public func detectCapabilities() async throws -> FFmpegCapabilities {
        try await Task.detached(priority: .userInitiated) {
            var muxersPtr: UnsafeMutablePointer<CChar>?
            var encodersPtr: UnsafeMutablePointer<CChar>?
            let code = aff_detect_capabilities(&muxersPtr, &encodersPtr)
            guard code == 0 else {
                throw FFmpegEngineError.failed(reason: Self.lastError())
            }
            defer {
                if let muxersPtr { aff_free_string(muxersPtr) }
                if let encodersPtr { aff_free_string(encodersPtr) }
            }

            let muxers = Self.parseJsonArray(muxersPtr)
            let encoders = Self.parseJsonArray(encodersPtr)
            return FFmpegCapabilities(muxers: Set(muxers), encoders: Set(encoders))
        }.value
    }

    public func execute(job: FFmpegJob, callbacks: FFmpegCallbacks) async throws -> FFmpegResult {
        try await Task.detached(priority: .userInitiated) {
            guard let cJob = aff_create_job() else {
                throw FFmpegEngineError.failed(reason: Self.lastError())
            }
            defer { aff_destroy_job(cJob) }

            let setIO = aff_set_input_output(cJob, job.input.path, job.output.path, job.overwriteExisting ? 1 : 0)
            guard setIO == 0 else {
                throw FFmpegEngineError.failed(reason: Self.lastError())
            }

            let argsStorage = job.arguments.map { strdup($0) }
            defer {
                for ptr in argsStorage {
                    if let ptr { free(ptr) }
                }
            }

            var argPtrs: [UnsafePointer<CChar>?] = argsStorage.map { ptr in
                ptr.map { UnsafePointer<CChar>($0) }
            }
            let setArgs = argPtrs.withUnsafeMutableBufferPointer { buffer -> Int32 in
                aff_set_arguments(cJob, buffer.baseAddress, Int32(buffer.count))
            }
            guard setArgs == 0 else {
                throw FFmpegEngineError.failed(reason: Self.lastError())
            }

            if let mediaEdit = job.mediaEditConfig {
                let setInputsCode = aff_set_media_edit_inputs(
                    cJob,
                    mediaEdit.additionalAudioInput?.path,
                    mediaEdit.subtitleInput?.path,
                    mediaEdit.subtitleCodec
                )
                guard setInputsCode == 0 else {
                    throw FFmpegEngineError.failed(reason: Self.lastError())
                }

                for (key, value) in mediaEdit.metadata.sorted(by: { $0.key < $1.key }) {
                    let addMetadataCode = aff_add_metadata(cJob, key, value)
                    guard addMetadataCode == 0 else {
                        throw FFmpegEngineError.failed(reason: Self.lastError())
                    }
                }

                let clearChaptersCode = aff_clear_chapters(cJob)
                guard clearChaptersCode == 0 else {
                    throw FFmpegEngineError.failed(reason: Self.lastError())
                }
                for chapter in mediaEdit.chapters {
                    let addChapterCode = aff_add_chapter(
                        cJob,
                        Int64(chapter.startMilliseconds),
                        Int64(chapter.endMilliseconds),
                        chapter.title
                    )
                    guard addChapterCode == 0 else {
                        throw FFmpegEngineError.failed(reason: Self.lastError())
                    }
                }
            }

            let callbackBox = CallbackBox(callbacks: callbacks)
            let retained = Unmanaged.passRetained(callbackBox)
            defer { retained.release() }

            Self.runningJobsQueue.sync {
                Self.runningJobs[job.id] = cJob
            }

            callbacks.onState(.started)

            let runCode = aff_run_job_async(
                cJob,
                { level, message, rawContext in
                    guard let rawContext, let message else { return }
                    let box = Unmanaged<CallbackBox>.fromOpaque(rawContext).takeUnretainedValue()
                    let text = String(cString: message)
                    let logLevel: FFmpegLogLevel = (level >= 2) ? .error : ((level == 1) ? .warning : .info)
                    box.callbacks.onLog(logLevel, text)
                },
                { progress, rawContext in
                    guard let rawContext else { return }
                    let box = Unmanaged<CallbackBox>.fromOpaque(rawContext).takeUnretainedValue()
                    let estimated = progress.estimated_ratio > 0 ? progress.estimated_ratio : nil
                    let processed = progress.processed_time_seconds > 0 ? progress.processed_time_seconds : nil
                    let frames = progress.processed_frames > 0 ? Double(progress.processed_frames) : nil
                    let bitrate = progress.bitrate_kbps > 0 ? progress.bitrate_kbps : nil
                    let speed = progress.speed > 0 ? progress.speed : nil
                    box.callbacks.onProgress(
                        FFmpegProgress(
                            processedFrames: frames,
                            processedTimeSeconds: processed,
                            estimatedRatio: estimated,
                            bitrateKbps: bitrate,
                            speed: speed
                        )
                    )
                },
                retained.toOpaque()
            )

            _ = Self.runningJobsQueue.sync {
                Self.runningJobs.removeValue(forKey: job.id)
            }

            guard runCode == 0 else {
                let reason = Self.lastError()
                if reason.contains("cancel") {
                    callbacks.onState(.cancelled)
                } else {
                    callbacks.onState(.failed(reason))
                }
                throw FFmpegEngineError.failed(reason: reason)
            }

            callbacks.onProgress(FFmpegProgress(estimatedRatio: 1))
            callbacks.onState(.completed)
            return FFmpegResult(exitCode: 0)
        }.value
    }

    public func cancel(jobID: UUID) {
        let jobPtr = Self.runningJobsQueue.sync {
            Self.runningJobs[jobID]
        }
        guard let jobPtr else { return }
        _ = aff_cancel_job(jobPtr)
    }

    public static func commandArguments(
        input: URL,
        output: URL,
        overwriteExisting: Bool,
        extraArguments: [String]
    ) -> [String] {
        let overwriteFlag = overwriteExisting ? "-y" : "-n"
        return [overwriteFlag, "-i", input.path] + extraArguments + [output.path]
    }

    public static func commandString(executable: String = "ffmpeg", arguments: [String]) -> String {
        ([executable] + arguments).map { shellEscaped($0) }.joined(separator: " ")
    }

    private static func shellEscaped(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let chars = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "'\"\\$`!"))
        if value.rangeOfCharacter(from: chars) == nil {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func parseJsonArray(_ cString: UnsafeMutablePointer<CChar>?) -> [String] {
        guard let cString else { return [] }
        let raw = String(cString: cString)
        guard let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String]) ?? []
    }

    private static func lastError() -> String {
        guard let ptr = aff_copy_last_error() else {
            return "unknown ffmpeg error"
        }
        let text = String(cString: ptr)
        return text.isEmpty ? "unknown ffmpeg error" : text
    }
}
