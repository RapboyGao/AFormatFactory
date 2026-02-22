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
    let duration: Double
    let showCropOverlay: Bool
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 8) {
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
                } else {
                    ContentUnavailableView("未选择预览文件", systemImage: "video.slash")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(minHeight: 260)

            controlBar
        }
        .onAppear {
            scrubValue = playhead
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
            if isScrubbing {
                return
            }
            scrubValue = newValue
            let current = session.player.currentTime().seconds
            if current.isFinite && abs(current - newValue) > 0.2 {
                session.seek(seconds: newValue)
            }
        }
        .onReceive(
            Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
        ) { _ in
            guard !isScrubbing, url != nil else { return }
            let seconds = session.player.currentTime().seconds
            guard seconds.isFinite else { return }
            if abs(seconds - playhead) > 0.2 {
                playhead = max(0, seconds)
                scrubValue = playhead
            }
            if duration > 0, seconds >= duration - 0.05, isPlaying {
                isPlaying = false
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button(isPlaying ? "暂停" : "播放") {
                    isPlaying.toggle()
                }
                .buttonStyle(MaterialActionButtonStyle())
                .disabled(url == nil)

                Text(timeString(isScrubbing ? scrubValue : playhead))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 56, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : playhead },
                        set: { value in
                            scrubValue = value
                            playhead = value
                        }
                    ),
                    in: 0...max(duration, 0.001),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            session.seek(seconds: scrubValue)
                        }
                    }
                )
                .disabled(url == nil || duration <= 0)

                Text(timeString(duration))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 56, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.36))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func timeString(_ seconds: Double) -> String {
        let value = max(0, seconds.isFinite ? seconds : 0)
        let total = Int(value.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private struct PlayerHostView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
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
        duration: 0,
        showCropOverlay: true
    )
    .padding()
    .background(.ultraThinMaterial)
    .frame(width: 800, height: 450)
}
