import Foundation
import CoreGraphics
import AFormatFactoryFFmpegKit

enum VideoRateControl: String, CaseIterable, Identifiable, Codable {
    case constantQuality
    case targetBitrate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .constantQuality:
            return "恒定质量 (CRF)"
        case .targetBitrate:
            return "目标码率"
        }
    }
}

enum ConversionPreset: String, CaseIterable, Identifiable, Codable {
    case highQuality
    case balanced
    case smallSize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highQuality:
            return "高质量"
        case .balanced:
            return "均衡"
        case .smallSize:
            return "小体积"
        }
    }
}

enum VideoEncoderOption: String, CaseIterable, Identifiable, Codable {
    case auto
    case h264
    case h265
    case av1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "自动"
        case .h264:
            return "H.264"
        case .h265:
            return "H.265"
        case .av1:
            return "AV1"
        }
    }
}

enum VideoScalePreset: String, CaseIterable, Identifiable, Codable {
    case source
    case p2160
    case p1440
    case p1080
    case p720
    case p480

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .source:
            return "保持原始"
        case .p2160:
            return "4K (2160p)"
        case .p1440:
            return "2K (1440p)"
        case .p1080:
            return "1080p"
        case .p720:
            return "720p"
        case .p480:
            return "480p"
        }
    }

    var height: Int? {
        switch self {
        case .source:
            return nil
        case .p2160:
            return 2160
        case .p1440:
            return 1440
        case .p1080:
            return 1080
        case .p720:
            return 720
        case .p480:
            return 480
        }
    }
}

enum VideoPresetOption: String, CaseIterable, Identifiable, Codable {
    case none
    case ultrafast
    case superfast
    case veryfast
    case faster
    case fast
    case medium
    case slow
    case slower
    case veryslow

    var id: String { rawValue }

    var displayName: String {
        self == .none ? "默认" : rawValue
    }
}

enum VideoRotateOption: String, CaseIterable, Identifiable, Codable {
    case none
    case clockwise90
    case counterClockwise90
    case rotate180

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "不旋转"
        case .clockwise90:
            return "顺时针90°"
        case .counterClockwise90:
            return "逆时针90°"
        case .rotate180:
            return "180°"
        }
    }
}

enum AudioCodecOption: String, CaseIterable, Identifiable, Codable {
    case auto
    case aac
    case mp3
    case opus
    case vorbis
    case flac
    case alac
    case pcmS16le

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "自动"
        case .aac:
            return "AAC"
        case .mp3:
            return "MP3 (LAME)"
        case .opus:
            return "Opus"
        case .vorbis:
            return "Vorbis"
        case .flac:
            return "FLAC"
        case .alac:
            return "ALAC"
        case .pcmS16le:
            return "PCM S16LE"
        }
    }

    var ffmpegCodecName: String? {
        switch self {
        case .auto:
            return nil
        case .aac:
            return "aac"
        case .mp3:
            return "libmp3lame"
        case .opus:
            return "libopus"
        case .vorbis:
            return "libvorbis"
        case .flac:
            return "flac"
        case .alac:
            return "alac"
        case .pcmS16le:
            return "pcm_s16le"
        }
    }
}

enum ConversionTaskStatus: String {
    case queued
    case running
    case succeeded
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .queued:
            return "排队中"
        case .running:
            return "执行中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        case .cancelled:
            return "已终止"
        }
    }
}

enum OutputLocationMode: String, CaseIterable, Identifiable {
    case sourceDirectory
    case specifiedDirectory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sourceDirectory:
            return "源文件目录"
        case .specifiedDirectory:
            return "指定目录"
        }
    }
}

enum MediaEditOutputFormat: String, CaseIterable, Identifiable {
    case sameAsSource
    case mp4
    case mkv
    case mov

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sameAsSource: return "与源文件一致"
        case .mp4: return "MP4"
        case .mkv: return "MKV"
        case .mov: return "MOV"
        }
    }

    func resolvedExtension(source: URL) -> String {
        switch self {
        case .sameAsSource:
            return source.pathExtension.isEmpty ? "mp4" : source.pathExtension.lowercased()
        case .mp4, .mkv, .mov:
            return rawValue
        }
    }
}

enum MediaEditOutputLocationMode: String, CaseIterable, Identifiable {
    case sourceDirectory
    case specifiedDirectory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sourceDirectory:
            return "源文件目录"
        case .specifiedDirectory:
            return "指定目录"
        }
    }
}

struct MediaEditChapter: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var startTime: String
    var endTime: String
    var title: String
}

struct ConversionTask: Identifiable {
    let id: UUID
    let createdAt: Date
    let inputURL: URL
    let outputURL: URL
    let format: ConversionFormat
    let domain: ConversionDomain
    let overwriteExisting: Bool
    let extraArguments: [String]
    let optionsSummary: String
    let sourceDurationSeconds: Double?
    let estimatedTotalFrames: Double?

    var status: ConversionTaskStatus
    var startedAt: Date?
    var finishedAt: Date?
    var logs: String
    var progress: Double
    var processedFrames: Double?
    var processedTimeSeconds: Double?
    var bitrateKbps: Double?
    var speed: Double?
}

@MainActor
public final class ContentViewModel: ObservableObject {
    static let defaultConcurrentTaskCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
    static let defaultOutputDirectoryURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("FFOutput", isDirectory: true)
    }()

    @Published var domain: ConversionDomain = .video {
        didSet {
            ensureFormatMatchesDomain()
            if let previewTargetFile, selectedFiles.contains(previewTargetFile) == false {
                self.previewTargetFile = nil
            }
            refreshPreviewTargetIfNeeded()
        }
    }

    @Published var selectedVideoFiles: [URL] = []
    @Published var selectedAudioFiles: [URL] = []
    @Published var outputLocationMode: OutputLocationMode = .specifiedDirectory
    @Published var outputDirectory: URL? = ContentViewModel.defaultOutputDirectoryURL
    @Published var format: ConversionFormat = .mp4
    @Published var supportedFormats: Set<ConversionFormat> = Set(ConversionFormat.allCases)

    @Published var overwriteExistingFiles = true
    @Published var conversionPreset: ConversionPreset = .balanced {
        didSet { applyPreset() }
    }

    // Video advanced settings
    @Published var copyVideoStream = false
    @Published var videoRateControl: VideoRateControl = .constantQuality
    @Published var videoEncoder: VideoEncoderOption = .auto
    @Published var videoScalePreset: VideoScalePreset = .source
    @Published var videoPreset: VideoPresetOption = .medium
    @Published var videoPixelFormat: String = "yuv420p"
    @Published var videoGOP: String = ""
    @Published var videoProfile: String = ""
    @Published var videoLevel: String = ""
    @Published var videoTune: String = ""
    @Published var videoCRF: Double = 23
    @Published var videoBitrateKbps: String = "2500"
    @Published var videoMaxBitrateKbps: String = ""
    @Published var videoBufferSizeKbps: String = ""
    @Published var videoFrameRate: String = ""
    @Published var enableDeinterlace = false
    @Published var videoRotate: VideoRotateOption = .none
    @Published var videoFlipHorizontal = false
    @Published var videoFlipVertical = false
    @Published var videoCropWidth: String = ""
    @Published var videoCropHeight: String = ""
    @Published var videoCropX: String = ""
    @Published var videoCropY: String = ""

    // Audio advanced settings
    @Published var copyAudioStream = false
    @Published var audioCodec: AudioCodecOption = .auto
    @Published var audioBitrateKbps: String = "192"
    @Published var audioSampleRate: String = "44100"
    @Published var audioChannels: Int = 2
    @Published var audioVolumeDB: String = ""
    @Published var audioVBRQuality: String = ""
    @Published var enableLoudnorm = false
    @Published var loudnormIntegratedTarget: String = "-16"
    @Published var loudnormLraTarget: String = "11"
    @Published var loudnormTruePeakTarget: String = "-1.5"
    @Published var selectedAudioTrackIndex: String = ""

    // General expert settings
    @Published var keepMetadata = true
    @Published var enableFastStart = true
    @Published var startTime: String = ""
    @Published var duration: String = ""
    @Published var threadCount: String = ""
    @Published var customFFmpegArgs: String = ""

    // Media editor (single-video)
    @Published var mediaEditInputVideoURL: URL?
    @Published var mediaEditOutputLocationMode: MediaEditOutputLocationMode = .sourceDirectory
    @Published var mediaEditOutputDirectory: URL?
    @Published var mediaEditOutputFormat: MediaEditOutputFormat = .sameAsSource
    @Published var mediaEditOverwriteExisting = true
    @Published var mediaEditAdditionalAudioURL: URL?
    @Published var mediaEditSubtitleURL: URL?
    @Published var mediaEditMetadataTitle: String = ""
    @Published var mediaEditMetadataArtist: String = ""
    @Published var mediaEditMetadataAlbum: String = ""
    @Published var mediaEditMetadataComment: String = ""
    @Published var mediaEditMetadataYear: String = ""
    @Published var mediaEditMetadataGenre: String = ""
    @Published var mediaEditMetadataCopyright: String = ""
    @Published var mediaEditMetadataLanguage: String = ""
    @Published var mediaEditChapters: [MediaEditChapter] = []
    @Published var mediaEditIsProcessing = false
    @Published var mediaEditLogs: String = ""
    var mediaEditActiveJobID: UUID?

    // Preview/editor state
    @Published var previewTargetFile: URL?
    @Published var previewTimeRangeStart: Double = 0
    @Published var previewTimeRangeEnd: Double?
    @Published var previewPlayheadSeconds: Double = 0
    @Published var previewZoom: Double = 1
    @Published var isPreviewPlaying = false
    @Published var editorMode: PreviewEditorMode = .crop
    @Published var previewAspectPreset: PreviewAspectPreset = .free
    @Published var previewCropRect: NormalizedCropRect = .full
    @Published var previewTransformState: PreviewTransformState = .identity
    @Published var filterGraph: FilterGraph = .empty
    @Published var previewVideoSize: CGSize?
    @Published var previewDurationSeconds: Double = 0
    @Published var showCopyDisabledHint = false

    // Queue controls
    @Published var tasks: [ConversionTask] = []
    @Published var selectedTaskIDs: Set<UUID> = []
    @Published var maxConcurrentTasks: Int = ContentViewModel.defaultConcurrentTaskCount
    @Published var isProcessingQueue = false
    @Published var appLogs = ""

    let engine: FFmpegEngineProtocol
    var capabilities: FFmpegCapabilities?
    var previewUndoStack: [PreviewSnapshot] = []
    var previewRedoStack: [PreviewSnapshot] = []
    var isSyncingPreviewState = false

    public init(engine: FFmpegEngineProtocol = FFmpegEngine()) {
        self.engine = engine
        applyPreset()
        try? FileManager.default.createDirectory(at: ContentViewModel.defaultOutputDirectoryURL, withIntermediateDirectories: true)
        Task {
            await refreshSupportedFormats()
        }
    }

    var selectedFiles: [URL] {
        domain == .video ? selectedVideoFiles : selectedAudioFiles
    }

    var availableFormats: [ConversionFormat] {
        ConversionFormat.formats(for: domain).filter { supportedFormats.contains($0) }
    }

    var selectedTask: ConversionTask? {
        tasks.first(where: { selectedTaskIDs.contains($0.id) })
    }

    var canTerminateSelectedTask: Bool {
        tasks.contains { selectedTaskIDs.contains($0.id) && ($0.status == .queued || $0.status == .running) }
    }

    var maxConcurrentTaskLimit: Int {
        max(1, ProcessInfo.processInfo.activeProcessorCount)
    }
}
