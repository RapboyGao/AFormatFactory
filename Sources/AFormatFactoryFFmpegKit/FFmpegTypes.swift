import Foundation

public struct FFmpegCapabilities: Sendable {
    public let muxers: Set<String>
    public let encoders: Set<String>

    public init(muxers: Set<String>, encoders: Set<String>) {
        self.muxers = muxers
        self.encoders = encoders
    }
}

public enum FFmpegLogLevel: String, Sendable {
    case info
    case warning
    case error
}

public enum FFmpegExecutionState: Sendable {
    case started
    case completed
    case failed(String)
    case cancelled
}

public struct FFmpegProgress: Sendable {
    public let processedFrames: Double?
    public let processedTimeSeconds: Double?
    public let estimatedRatio: Double?
    public let bitrateKbps: Double?
    public let speed: Double?

    public init(
        processedFrames: Double? = nil,
        processedTimeSeconds: Double? = nil,
        estimatedRatio: Double? = nil,
        bitrateKbps: Double? = nil,
        speed: Double? = nil
    ) {
        self.processedFrames = processedFrames
        self.processedTimeSeconds = processedTimeSeconds
        self.estimatedRatio = estimatedRatio
        self.bitrateKbps = bitrateKbps
        self.speed = speed
    }
}

public struct FFmpegResult: Sendable {
    public let exitCode: Int32

    public init(exitCode: Int32) {
        self.exitCode = exitCode
    }
}

public struct FFmpegMediaInfo: Sendable {
    public let durationSeconds: Double?
    public let streamCount: Int

    public init(durationSeconds: Double?, streamCount: Int) {
        self.durationSeconds = durationSeconds
        self.streamCount = streamCount
    }
}

public struct FFmpegJob: Sendable {
    public let id: UUID
    public let input: URL
    public let output: URL
    public let overwriteExisting: Bool
    public let arguments: [String]
    public let mediaEditConfig: FFmpegMediaEditConfig?
    public let estimatedDurationSeconds: Double?
    public let estimatedTotalFrames: Double?

    public init(
        id: UUID,
        input: URL,
        output: URL,
        overwriteExisting: Bool,
        arguments: [String],
        mediaEditConfig: FFmpegMediaEditConfig? = nil,
        estimatedDurationSeconds: Double? = nil,
        estimatedTotalFrames: Double? = nil
    ) {
        self.id = id
        self.input = input
        self.output = output
        self.overwriteExisting = overwriteExisting
        self.arguments = arguments
        self.mediaEditConfig = mediaEditConfig
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.estimatedTotalFrames = estimatedTotalFrames
    }
}

public struct FFmpegMediaEditChapter: Sendable {
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    public let title: String

    public init(startMilliseconds: Int, endMilliseconds: Int, title: String) {
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.title = title
    }
}

public struct FFmpegMediaEditConfig: Sendable {
    public let additionalAudioInput: URL?
    public let subtitleInput: URL?
    public let subtitleCodec: String
    public let metadata: [String: String]
    public let chapters: [FFmpegMediaEditChapter]

    public init(
        additionalAudioInput: URL? = nil,
        subtitleInput: URL? = nil,
        subtitleCodec: String = "copy",
        metadata: [String: String] = [:],
        chapters: [FFmpegMediaEditChapter] = []
    ) {
        self.additionalAudioInput = additionalAudioInput
        self.subtitleInput = subtitleInput
        self.subtitleCodec = subtitleCodec
        self.metadata = metadata
        self.chapters = chapters
    }
}

public struct FFmpegCallbacks: Sendable {
    public let onLog: @Sendable (FFmpegLogLevel, String) -> Void
    public let onProgress: @Sendable (FFmpegProgress) -> Void
    public let onState: @Sendable (FFmpegExecutionState) -> Void

    public init(
        onLog: @escaping @Sendable (FFmpegLogLevel, String) -> Void,
        onProgress: @escaping @Sendable (FFmpegProgress) -> Void,
        onState: @escaping @Sendable (FFmpegExecutionState) -> Void
    ) {
        self.onLog = onLog
        self.onProgress = onProgress
        self.onState = onState
    }
}

public protocol FFmpegEngineProtocol: Sendable {
    func probe(url: URL) async throws -> FFmpegMediaInfo
    func detectCapabilities() async throws -> FFmpegCapabilities
    func execute(job: FFmpegJob, callbacks: FFmpegCallbacks) async throws -> FFmpegResult
    func cancel(jobID: UUID)
}
