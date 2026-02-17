import AVKit
import SwiftUI

struct PreviewPlayerView: View {
    @ObservedObject var session: PreviewSessionStore
    let url: URL?
    @Binding var cropRect: NormalizedCropRect
    @Binding var aspectPreset: PreviewAspectPreset
    @Binding var transform: PreviewTransformState
    @Binding var playhead: Double
    @Binding var isPlaying: Bool
    let showCropOverlay: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.3))

            if url != nil {
                PlayerHostView(player: session.player)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        if showCropOverlay {
                            PreviewOverlayView(cropRect: $cropRect, aspectPreset: $aspectPreset)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .onAppear {
                        Task { await session.load(url: url) }
                    }
                    .onChange(of: url) { _, newValue in
                        Task { await session.load(url: newValue) }
                    }
                    .onChange(of: isPlaying) { _, playing in
                        if playing {
                            session.player.play()
                        } else {
                            session.player.pause()
                        }
                    }
                    .onChange(of: playhead) { _, newValue in
                        if abs(session.player.currentTime().seconds - newValue) > 0.2 {
                            session.seek(seconds: newValue)
                        }
                    }
            } else {
                ContentUnavailableView("未选择预览文件", systemImage: "video.slash")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(minHeight: 260)
    }
}

private struct PlayerHostView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

#Preview {
    PreviewPlayerView(
        session: PreviewSessionStore(),
        url: nil,
        cropRect: .constant(.full),
        aspectPreset: .constant(.free),
        transform: .constant(.identity),
        playhead: .constant(0),
        isPlaying: .constant(false),
        showCropOverlay: true
    )
    .padding()
    .background(.ultraThinMaterial)
    .frame(width: 800, height: 450)
}
