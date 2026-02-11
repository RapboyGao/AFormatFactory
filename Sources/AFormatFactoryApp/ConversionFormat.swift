import Foundation

enum ConversionFormat: String, CaseIterable, Identifiable {
    case mp4
    case mov
    case mkv
    case mp3
    case wav
    case gif

    var id: String { rawValue }

    var outputExtension: String { rawValue }

    var displayName: String {
        rawValue.uppercased()
    }

    var extraArguments: [String] {
        switch self {
        case .mp4:
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "192k"]
        case .mov:
            return ["-c:v", "libx264", "-c:a", "aac", "-b:a", "192k"]
        case .mkv:
            return ["-c:v", "libx264", "-c:a", "aac", "-b:a", "192k"]
        case .mp3:
            return ["-vn", "-c:a", "libmp3lame", "-b:a", "192k"]
        case .wav:
            return ["-vn", "-c:a", "pcm_s16le"]
        case .gif:
            return ["-vf", "fps=12,scale=960:-1:flags=lanczos"]
        }
    }
}
