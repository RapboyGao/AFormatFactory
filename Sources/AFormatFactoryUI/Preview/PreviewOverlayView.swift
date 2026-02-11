import SwiftUI

struct PreviewOverlayView: View {
    @Binding var cropRect: NormalizedCropRect
    @Binding var aspectPreset: PreviewAspectPreset

    private let handleSize: CGFloat = 10
    @State private var moveStartRect: NormalizedCropRect?
    @State private var resizeStartRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let frame = rect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.2)
                    .mask {
                        Rectangle()
                            .overlay {
                                Rectangle()
                                    .frame(width: frame.width, height: frame.height)
                                    .offset(x: frame.minX, y: frame.minY)
                                    .blendMode(.destinationOut)
                            }
                    }

                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .gesture(moveGesture(size: proxy.size))

                ForEach(HandleAnchor.allCases, id: \.self) { anchor in
                    Circle()
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .position(position(for: anchor, in: frame))
                        .gesture(resizeGesture(anchor: anchor, size: proxy.size))
                }
            }
        }
    }

    private func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: cropRect.x * size.width,
            y: cropRect.y * size.height,
            width: cropRect.width * size.width,
            height: cropRect.height * size.height
        )
    }

    private func position(for anchor: HandleAnchor, in rect: CGRect) -> CGPoint {
        switch anchor {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func moveGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = moveStartRect ?? cropRect
                moveStartRect = base
                var rect = base
                rect.x = base.x + value.translation.width / size.width
                rect.y = base.y + value.translation.height / size.height
                cropRect = rect.clamped()
            }
            .onEnded { _ in
                moveStartRect = nil
            }
    }

    private func resizeGesture(anchor: HandleAnchor, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let baseRect = resizeStartRect ?? rect(in: size)
                resizeStartRect = baseRect
                var pxRect = baseRect
                let dx = value.translation.width
                let dy = value.translation.height

                switch anchor {
                case .topLeft:
                    pxRect.origin.x += dx
                    pxRect.size.width -= dx
                    pxRect.origin.y += dy
                    pxRect.size.height -= dy
                case .top:
                    pxRect.origin.y += dy
                    pxRect.size.height -= dy
                case .topRight:
                    pxRect.size.width += dx
                    pxRect.origin.y += dy
                    pxRect.size.height -= dy
                case .left:
                    pxRect.origin.x += dx
                    pxRect.size.width -= dx
                case .right:
                    pxRect.size.width += dx
                case .bottomLeft:
                    pxRect.origin.x += dx
                    pxRect.size.width -= dx
                    pxRect.size.height += dy
                case .bottom:
                    pxRect.size.height += dy
                case .bottomRight:
                    pxRect.size.width += dx
                    pxRect.size.height += dy
                }

                if let ratio = aspectPreset.ratio {
                    let width = max(20, pxRect.width)
                    let height = max(20, width / ratio)
                    pxRect.size = CGSize(width: width, height: height)
                }

                pxRect.size.width = max(20, min(pxRect.width, size.width))
                pxRect.size.height = max(20, min(pxRect.height, size.height))
                pxRect.origin.x = max(0, min(pxRect.origin.x, size.width - pxRect.width))
                pxRect.origin.y = max(0, min(pxRect.origin.y, size.height - pxRect.height))

                cropRect = NormalizedCropRect(
                    x: pxRect.minX / size.width,
                    y: pxRect.minY / size.height,
                    width: pxRect.width / size.width,
                    height: pxRect.height / size.height
                ).clamped()
            }
            .onEnded { _ in
                resizeStartRect = nil
            }
    }
}

private enum HandleAnchor: CaseIterable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}

#Preview {
    PreviewOverlayView(cropRect: .constant(.init(x: 0.1, y: 0.1, width: 0.6, height: 0.6)), aspectPreset: .constant(.free))
        .frame(width: 700, height: 420)
        .background(.black)
}
