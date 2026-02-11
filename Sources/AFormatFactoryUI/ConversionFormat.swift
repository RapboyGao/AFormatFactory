import Foundation

enum ConversionDomain: String, CaseIterable, Identifiable {
    case video
    case audio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .video:
            return "视频格式转换"
        case .audio:
            return "音频格式转换"
        }
    }
}

enum ConversionFormat: String, CaseIterable, Identifiable {
    case mp4
    case mov
    case mkv
    case webm
    case avi
    case flv
    case m4v
    case ts
    case mpeg
    case ogv
    case `3gp`
    case mp3
    case wav
    case m4a
    case aac
    case flac
    case ogg
    case opus
    case aiff
    case wma
    case alac
    case gif

    var id: String { rawValue }

    var outputExtension: String {
        switch self {
        case .aiff:
            return "aif"
        case .`3gp`:
            return "3gp"
        default:
            return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .m4a:
            return "M4A (AAC)"
        case .aac:
            return "AAC"
        case .alac:
            return "ALAC (M4A)"
        case .aiff:
            return "AIFF"
        case .`3gp`:
            return "3GP"
        default:
            return rawValue.uppercased()
        }
    }

    var domain: ConversionDomain {
        switch self {
        case .mp4, .mov, .mkv, .webm, .avi, .flv, .m4v, .ts, .mpeg, .ogv, .`3gp`, .gif:
            return .video
        case .mp3, .wav, .m4a, .aac, .flac, .ogg, .opus, .aiff, .wma, .alac:
            return .audio
        }
    }

    static func formats(for domain: ConversionDomain) -> [ConversionFormat] {
        allCases.filter { $0.domain == domain }
    }

    var extraArguments: [String] {
        switch self {
        case .mp4:
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "192k"]
        case .mov:
            return ["-c:v", "libx264", "-c:a", "aac", "-b:a", "192k"]
        case .mkv:
            return ["-c:v", "libx264", "-c:a", "aac", "-b:a", "192k"]
        case .webm:
            return ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-c:a", "libopus", "-b:a", "128k"]
        case .avi:
            return ["-c:v", "mpeg4", "-q:v", "5", "-c:a", "libmp3lame", "-b:a", "192k"]
        case .flv:
            return ["-c:v", "flv", "-c:a", "libmp3lame", "-b:a", "128k"]
        case .m4v:
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "192k"]
        case .ts:
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "192k", "-f", "mpegts"]
        case .mpeg:
            return ["-c:v", "mpeg2video", "-q:v", "3", "-c:a", "mp2", "-b:a", "192k"]
        case .ogv:
            return ["-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "5"]
        case .`3gp`:
            return ["-c:v", "h263", "-s", "352x288", "-r", "25", "-c:a", "aac", "-b:a", "96k"]
        case .mp3:
            return ["-vn", "-c:a", "libmp3lame", "-b:a", "192k"]
        case .wav:
            return ["-vn", "-c:a", "pcm_s16le"]
        case .m4a:
            return ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case .aac:
            return ["-vn", "-c:a", "aac", "-b:a", "192k", "-f", "adts"]
        case .flac:
            return ["-vn", "-c:a", "flac"]
        case .ogg:
            return ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
        case .opus:
            return ["-vn", "-c:a", "libopus", "-b:a", "160k"]
        case .aiff:
            return ["-vn", "-c:a", "pcm_s16be"]
        case .wma:
            return ["-vn", "-c:a", "wmav2", "-b:a", "192k"]
        case .alac:
            return ["-vn", "-c:a", "alac"]
        case .gif:
            return ["-vf", "fps=12,scale=960:-1:flags=lanczos"]
        }
    }
}
