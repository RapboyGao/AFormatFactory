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
                                width: max(proxy.size.width * 0.7, image.size.width * viewModel.imageFullscreenZoom),
                                height: max(proxy.size.height * 0.7, image.size.height * viewModel.imageFullscreenZoom)
                            )
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
                    HStack(spacing: 10) {
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
                .background(
                    ImageFullscreenInteractionView(
                        onScroll: { deltaY in
                            viewModel.adjustFullscreenImageZoom(with: deltaY)
                        },
                        onLeftClick: {
                            viewModel.showNextImage()
                        },
                        onRightClick: {
                            viewModel.showPreviousImage()
                        }
                    )
                )
            }
        }
        .zIndex(999)
    }
}

private struct ImageFullscreenInteractionView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onLeftClick: () -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onScroll = onScroll
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
    }
}

private final class InteractionNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }

    override func mouseDown(with event: NSEvent) {
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

#Preview {
    ImageFullscreenOverlayView(viewModel: ContentViewModel())
        .frame(width: 1200, height: 800)
}
