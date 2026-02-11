import SwiftUI

struct MaterialActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.45))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial.opacity(configuration.isPressed ? 0.45 : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.18 : 0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MaterialToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.thinMaterial.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .frame(width: 40, height: 22)

                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct VideoRateControlSegmentedControl: View {
    @Binding var selection: VideoRateControl

    var body: some View {
        HStack(spacing: 6) {
            segmentButton(.constantQuality)
            segmentButton(.targetBitrate)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func segmentButton(_ option: VideoRateControl) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            Text(option.displayName)
                .lineLimit(1)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white.opacity(selected ? 0.98 : 0.82))
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.thinMaterial.opacity(selected ? 0.85 : 0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(selected ? 0.24 : 0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
