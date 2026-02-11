import Foundation

struct FFmpegFilterGraphBuilder {
    static func build(
        cropRect: NormalizedCropRect,
        transform: PreviewTransformState,
        videoScalePreset: VideoScalePreset,
        enableDeinterlace: Bool,
        videoFiltersFromNodes: [FilterNode],
        audioFiltersFromNodes: [FilterNode],
        loudnormTuple: (i: Double, lra: Double, tp: Double)?,
        audioVolumeDB: Double?
    ) -> (video: String?, audio: String?) {
        var videoFilters: [String] = []
        var audioFilters: [String] = []

        if cropRect != .full {
            let w = max(0.01, min(1, cropRect.width))
            let h = max(0.01, min(1, cropRect.height))
            let x = max(0, min(1, cropRect.x))
            let y = max(0, min(1, cropRect.y))
            videoFilters.append("crop=iw*\(fmt(w)):ih*\(fmt(h)):iw*\(fmt(x)):ih*\(fmt(y))")
        }

        if let height = videoScalePreset.height {
            videoFilters.append("scale=-2:\(height):flags=lanczos")
        }

        if enableDeinterlace {
            videoFilters.append("yadif")
        }

        switch transform.rotate {
        case .none:
            break
        case .clockwise90:
            videoFilters.append("transpose=1")
        case .counterClockwise90:
            videoFilters.append("transpose=2")
        case .rotate180:
            videoFilters.append("transpose=2,transpose=2")
        }

        if transform.flipHorizontal {
            videoFilters.append("hflip")
        }
        if transform.flipVertical {
            videoFilters.append("vflip")
        }

        videoFilters.append(contentsOf: render(nodes: videoFiltersFromNodes, onlyVideo: true))
        audioFilters.append(contentsOf: render(nodes: audioFiltersFromNodes, onlyVideo: false))

        if let vol = audioVolumeDB, vol != 0 {
            audioFilters.append("volume=\(String(format: "%.2f", vol))dB")
        }

        if let loudnormTuple {
            let i = String(format: "%.1f", loudnormTuple.i)
            let lra = String(format: "%.1f", loudnormTuple.lra)
            let tp = String(format: "%.1f", loudnormTuple.tp)
            audioFilters.append("loudnorm=I=\(i):LRA=\(lra):TP=\(tp)")
        }

        return (
            videoFilters.isEmpty ? nil : videoFilters.joined(separator: ","),
            audioFilters.isEmpty ? nil : audioFilters.joined(separator: ",")
        )
    }

    private static func render(nodes: [FilterNode], onlyVideo: Bool) -> [String] {
        nodes
            .filter { $0.enabled }
            .sorted(by: { $0.order < $1.order })
            .compactMap { node in
                if onlyVideo != node.kind.isVideo {
                    return nil
                }
                return render(node: node)
            }
    }

    private static func render(node: FilterNode) -> String {
        if node.params.isEmpty {
            return node.kind.rawValue
        }
        let body = node.params
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ":")
        return "\(node.kind.rawValue)=\(body)"
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
