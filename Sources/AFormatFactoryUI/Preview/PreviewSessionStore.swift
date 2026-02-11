import AVFoundation
import Foundation

@MainActor
final class PreviewSessionStore: ObservableObject {
    @Published var currentURL: URL?
    @Published var durationSeconds: Double = 0
    @Published var naturalVideoSize: CGSize?

    let player = AVPlayer()

    func load(url: URL?) async {
        guard currentURL != url else { return }
        currentURL = url

        guard let url else {
            player.replaceCurrentItem(with: nil)
            durationSeconds = 0
            naturalVideoSize = nil
            return
        }

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            durationSeconds = seconds.isFinite ? max(0, seconds) : 0
        } catch {
            durationSeconds = 0
        }

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                naturalVideoSize = CGSize(width: abs(size.width), height: abs(size.height))
            } else {
                naturalVideoSize = nil
            }
        } catch {
            naturalVideoSize = nil
        }
    }

    func seek(seconds: Double) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
