import SwiftUI

struct TimelineStripView: View {
    let totalDuration: Double
    @Binding var start: Double
    @Binding var end: Double?
    @Binding var playhead: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("时间轴")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            if totalDuration > 0 {
                HStack(spacing: 10) {
                    Text("入点")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Slider(value: $start, in: 0...totalDuration)
                    Text(secondsString(start))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Text("出点")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Slider(
                        value: Binding(
                            get: { end ?? totalDuration },
                            set: { end = $0 >= totalDuration - 0.001 ? nil : $0 }
                        ),
                        in: 0...totalDuration
                    )
                    Text(secondsString(end ?? totalDuration))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Text("播放")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Slider(value: $playhead, in: 0...totalDuration)
                    Text(secondsString(playhead))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }
            } else {
                Text("无可用时长")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func secondsString(_ value: Double) -> String {
        String(format: "%.3fs", max(0, value))
    }
}

#Preview {
    TimelineStripView(totalDuration: 124.2, start: .constant(5), end: .constant(92.8), playhead: .constant(13.1))
        .padding()
        .background(.ultraThinMaterial)
        .frame(width: 700, height: 220)
}
