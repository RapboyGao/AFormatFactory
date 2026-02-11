import Foundation

enum PreviewEditorMode: String, CaseIterable, Identifiable, Codable {
    case crop
    case transform
    case filter
    case audio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crop: return "裁剪"
        case .transform: return "变换"
        case .filter: return "滤镜链"
        case .audio: return "音频"
        }
    }
}

enum PreviewAspectPreset: String, CaseIterable, Identifiable {
    case free
    case ratio16x9
    case ratio9x16
    case ratio1x1

    var id: String { rawValue }

    var ratio: Double? {
        switch self {
        case .free: return nil
        case .ratio16x9: return 16.0 / 9.0
        case .ratio9x16: return 9.0 / 16.0
        case .ratio1x1: return 1.0
        }
    }

    var displayName: String {
        switch self {
        case .free: return "自由"
        case .ratio16x9: return "16:9"
        case .ratio9x16: return "9:16"
        case .ratio1x1: return "1:1"
        }
    }
}

struct NormalizedCropRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = NormalizedCropRect(x: 0, y: 0, width: 1, height: 1)

    func clamped() -> NormalizedCropRect {
        var rect = self
        rect.x = min(max(0, rect.x), 1)
        rect.y = min(max(0, rect.y), 1)
        rect.width = min(max(0.01, rect.width), 1)
        rect.height = min(max(0.01, rect.height), 1)
        if rect.x + rect.width > 1 {
            rect.x = max(0, 1 - rect.width)
        }
        if rect.y + rect.height > 1 {
            rect.y = max(0, 1 - rect.height)
        }
        return rect
    }
}

struct PreviewTransformState: Codable, Equatable {
    var rotate: VideoRotateOption
    var flipHorizontal: Bool
    var flipVertical: Bool
    var scale: Double
    var offsetX: Double
    var offsetY: Double

    static let identity = PreviewTransformState(
        rotate: .none,
        flipHorizontal: false,
        flipVertical: false,
        scale: 1,
        offsetX: 0,
        offsetY: 0
    )
}

enum FilterNodeKind: String, CaseIterable, Identifiable, Codable {
    case crop
    case scale
    case fps
    case eq
    case unsharp
    case hqdn3d
    case transpose
    case hflip
    case vflip

    case volume
    case loudnorm
    case afade
    case highpass
    case lowpass
    case aresample

    case drawtext
    case overlay

    var id: String { rawValue }

    var displayName: String {
        rawValue
    }

    var isVideo: Bool {
        switch self {
        case .crop, .scale, .fps, .eq, .unsharp, .hqdn3d, .transpose, .hflip, .vflip, .drawtext, .overlay:
            return true
        default:
            return false
        }
    }
}

struct FilterNode: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: FilterNodeKind
    var params: [String: String]
    var enabled: Bool
    var order: Int

    init(id: UUID = UUID(), kind: FilterNodeKind, params: [String: String] = [:], enabled: Bool = true, order: Int = 0) {
        self.id = id
        self.kind = kind
        self.params = params
        self.enabled = enabled
        self.order = order
    }
}

struct FilterGraph: Codable, Equatable {
    var videoNodes: [FilterNode]
    var audioNodes: [FilterNode]

    static let empty = FilterGraph(videoNodes: [], audioNodes: [])
}

struct PreviewSnapshot: Codable {
    var cropRect: NormalizedCropRect
    var transform: PreviewTransformState
    var timeRangeStart: Double
    var timeRangeEnd: Double?
    var filterGraph: FilterGraph
    var editorMode: PreviewEditorMode
}
