import AVFoundation
import SwiftUI

struct AudioPreviewView: View {
    let url: URL?
    @Binding var isPlaying: Bool
    @Binding var playhead: Double
    @State private var samples: [CGFloat] = []
    @State private var player: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(isPlaying ? "暂停" : "播放") {
                    togglePlayback()
                }
                .buttonStyle(MaterialActionButtonStyle())
                .disabled(url == nil)

                Text(url?.lastPathComponent ?? "未选择音频文件")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Spacer()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.3))

                if samples.isEmpty {
                    ContentUnavailableView("音频波形不可用", systemImage: "waveform")
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    GeometryReader { proxy in
                        let mid = proxy.size.height / 2
                        Path { path in
                            let step = max(1, samples.count / Int(max(1, proxy.size.width)))
                            var x: CGFloat = 0
                            for i in stride(from: 0, to: samples.count, by: step) {
                                let amp = samples[i] * (mid - 6)
                                path.move(to: CGPoint(x: x, y: mid - amp))
                                path.addLine(to: CGPoint(x: x, y: mid + amp))
                                x += 1
                            }
                        }
                        .stroke(.cyan.opacity(0.8), lineWidth: 1)

                        Rectangle()
                            .fill(.white.opacity(0.7))
                            .frame(width: 2)
                            .offset(x: max(0, min(proxy.size.width, proxy.size.width * CGFloat(normalizedPlayhead))))
                    }
                }
            }
            .frame(minHeight: 220)
        }
        .onAppear { loadWaveform() }
        .onChange(of: url) { _, _ in
            stopPlayback()
            loadWaveform()
        }
    }

    private var normalizedPlayhead: Double {
        guard let player, player.duration > 0 else { return 0 }
        return max(0, min(1, playhead / player.duration))
    }

    private func togglePlayback() {
        guard let url else { return }
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
            playhead = player.currentTime
        } else {
            player.currentTime = playhead
            player.play()
            isPlaying = true
            Task {
                while isPlaying {
                    await MainActor.run {
                        playhead = player.currentTime
                        if player.isPlaying == false {
                            isPlaying = false
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playhead = 0
    }

    private func loadWaveform() {
        guard let url else {
            samples = []
            return
        }

        Task.detached {
            let values = (try? Self.extractSamples(url: url)) ?? []
            await MainActor.run {
                samples = values
            }
        }
    }

    nonisolated private static func extractSamples(url: URL) throws -> [CGFloat] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = Int(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        guard let buffer else { return [] }

        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else { return [] }

        let channel = channelData[0]
        let total = Int(buffer.frameLength)
        guard total > 0 else { return [] }

        let target = 1800
        let strideValue = max(1, total / target)
        var result: [CGFloat] = []
        result.reserveCapacity(target)

        var idx = 0
        while idx < total {
            let end = min(total, idx + strideValue)
            var peak: Float = 0
            var s = idx
            while s < end {
                peak = max(peak, abs(channel[s]))
                s += 1
            }
            result.append(CGFloat(peak))
            idx = end
        }

        return result
    }
}

#Preview {
    AudioPreviewView(url: nil, isPlaying: .constant(false), playhead: .constant(0))
        .padding()
        .background(.ultraThinMaterial)
        .frame(width: 800, height: 360)
}
