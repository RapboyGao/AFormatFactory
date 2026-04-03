import SwiftUI
import AppKit

/// 图片沉浸式全屏层，仅覆盖应用窗口，不切换整个 App 的系统全屏状态。
struct ImageFullscreenOverlayView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.985)
                .ignoresSafeArea()

            if let image = viewModel.currentImage {
                GeometryReader { proxy in
                    ZStack {
                        Color.clear
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                maxWidth: proxy.size.width * 0.82,
                                maxHeight: proxy.size.height * 0.82
                            )
                            .scaleEffect(viewModel.imageFullscreenZoom)
                            .offset(viewModel.imageFullscreenOffset)
                            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.currentImageURL?.lastPathComponent ?? "")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("滚轮缩放 | 左键下一张 | 右键上一张")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(20)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 12) {
                        Toggle("自动播放", isOn: $viewModel.imageSlideshowEnabled)
                            .toggleStyle(MaterialToggleStyle())
                            .frame(width: 120)
                        Picker("间隔", selection: $viewModel.imageSlideshowInterval) {
                            Text("1s").tag(1.0)
                            Text("2s").tag(2.0)
                            Text("3s").tag(3.0)
                            Text("5s").tag(5.0)
                            Text("10s").tag(10.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 90)
                        Text("\(Int(viewModel.imageFullscreenZoom * 100))%")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                        Button("退出全屏") {
                            viewModel.dismissImageFullscreen()
                        }
                        .buttonStyle(MaterialActionButtonStyle())
                    }
                    .padding(20)
                }
                .overlay(
                    ImageFullscreenInteractionView(
                        onScroll: { deltaY in
                            viewModel.adjustFullscreenImageZoom(with: deltaY)
                        },
                        onDrag: { translation in
                            viewModel.dragFullscreenImage(by: translation)
                        },
                        onLeftClick: {
                            viewModel.showNextImage()
                        },
                        onRightClick: {
                            viewModel.showPreviousImage()
                        },
                        onKeyPress: { keyCode in
                            switch keyCode {
                            case 123:
                                viewModel.showPreviousImage()
                            case 124:
                                viewModel.showNextImage()
                            case 53:
                                viewModel.dismissImageFullscreen()
                            default:
                                break
                            }
                        }
                    )
                )
            }
        }
        .zIndex(999)
        .task(id: autoplayTaskID) {
            guard viewModel.imageFullscreenPresented, viewModel.imageSlideshowEnabled else { return }
            while viewModel.imageFullscreenPresented && viewModel.imageSlideshowEnabled {
                let duration = UInt64(max(1, viewModel.imageSlideshowInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: duration)
                guard viewModel.imageFullscreenPresented, viewModel.imageSlideshowEnabled else { break }
                await MainActor.run {
                    viewModel.showNextImage()
                }
            }
        }
    }

    private var autoplayTaskID: String {
        "\(viewModel.imageFullscreenPresented)-\(viewModel.imageSlideshowEnabled)-\(viewModel.imageSlideshowInterval)"
    }
}

private struct ImageFullscreenInteractionView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onDrag: (CGSize) -> Void
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onKeyPress: (UInt16) -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onScroll = onScroll
        view.onDrag = onDrag
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onKeyPress = onKeyPress
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onDrag = onDrag
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onKeyPress = onKeyPress
    }
}

private final class InteractionNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onKeyPress: ((UInt16) -> Void)?
    private var lastDragPoint: NSPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)
        if let lastDragPoint {
            let translation = CGSize(width: currentPoint.x - lastDragPoint.x, height: currentPoint.y - lastDragPoint.y)
            if abs(translation.width) > 1 || abs(translation.height) > 1 {
                didDrag = true
                onDrag?(translation)
            }
        }
        lastDragPoint = currentPoint
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onLeftClick?()
        }
        lastDragPoint = nil
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func keyDown(with event: NSEvent) {
        onKeyPress?(event.keyCode)
    }
}

#Preview {
    ImageFullscreenOverlayView(viewModel: ContentViewModel())
        .frame(width: 1200, height: 800)
}
