import SwiftUI

/// HEIC/HIF/HEIF 图片查看工作区，使用系统原生解码显示并支持导出 JPEG。
struct ImageViewerWorkspaceView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 12) {
            toolbarCard
            exportProgressCard
            contentCard
        }
    }

    private var toolbarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HEIC / HIF / HEIF 图片查看器")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer()

                Button("选择图片") {
                    viewModel.pickImageFiles()
                }
                .buttonStyle(MaterialActionButtonStyle())

                Button("批量导出 JPEG") {
                    viewModel.exportSelectedImagesAsJPEG()
                }
                .buttonStyle(MaterialActionButtonStyle())
                .disabled(viewModel.selectedImageFiles.isEmpty || viewModel.imageExportInProgress)

                Button("全屏预览") {
                    viewModel.presentImageFullscreen()
                }
                .buttonStyle(MaterialActionButtonStyle())
                .disabled(viewModel.currentImage == nil)
            }

            if let url = viewModel.currentImageURL {
                Text(url.path)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.76))
                    .textSelection(.enabled)
                    .lineLimit(2)
            } else {
                Text("选择一张或多张 HEIC/HIF/HEIF 图片后，可在左侧列表切换查看。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .cardStyle()
    }

    private var contentCard: some View {
        HStack(alignment: .top, spacing: 12) {
            fileList
                .frame(width: 320)
            previewPanel
        }
    }

    @ViewBuilder
    private var exportProgressCard: some View {
        if viewModel.imageExportInProgress || viewModel.imageExportCompletedCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("JPEG 导出进度")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                    Spacer()
                    Text("\(viewModel.imageExportCompletedCount)/\(max(1, viewModel.imageExportTotalCount))")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                }

                ProgressView(value: Double(viewModel.imageExportCompletedCount), total: Double(max(1, viewModel.imageExportTotalCount)))
                    .tint(.white)

                if let outputDirectory = viewModel.imageExportLastOutputDirectory {
                    Text(outputDirectory.path)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                }
            }
            .cardStyle()
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选图片（\(viewModel.selectedImageFiles.count)）")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                Spacer()
                Button("全选") {
                    viewModel.selectAllImageFiles()
                }
                .buttonStyle(MaterialActionButtonStyle())
                .disabled(viewModel.selectedImageFiles.isEmpty)
                Button("删除选中") {
                    viewModel.removeSelectedImageFiles()
                }
                .buttonStyle(MaterialActionButtonStyle())
                .disabled(viewModel.selectedImageFileSet.isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.selectedImageFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            Button {
                                viewModel.toggleImageFileSelection(file)
                            } label: {
                                Image(systemName: viewModel.selectedImageFileSet.contains(file) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedImageFileSet.contains(file) ? .white : .white.opacity(0.55))
                            }
                            .buttonStyle(.plain)

                            Button(viewModel.currentImageURL == file ? "查看中" : "查看") {
                                viewModel.setCurrentImage(file)
                            }
                            .buttonStyle(MaterialActionButtonStyle())

                            Text(file.lastPathComponent)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.86))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)

                            Button {
                                viewModel.removeSelectedImageFile(file)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.64))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(Color.white.opacity(viewModel.currentImageURL == file ? 0.12 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .cardStyle()
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("图片预览")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                Spacer()
                if viewModel.currentImageURL != nil {
                    Text(infoText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            if let image = viewModel.currentImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: max(180, image.size.width * viewModel.imageViewerZoom),
                            height: max(180, image.size.height * viewModel.imageViewerZoom)
                        )
                        .padding(18)
                        .onTapGesture(count: 2) {
                            viewModel.presentImageFullscreen()
                        }
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .background(Color.black.opacity(0.34))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 12) {
                    Text("缩放")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))

                    Slider(value: $viewModel.imageViewerZoom, in: 0.1...4.0)

                    Text("\(Int(viewModel.imageViewerZoom * 100))%")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.74))
                        .frame(width: 54, alignment: .trailing)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("暂无图片")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .background(Color.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .cardStyle()
    }

    private var infoText: String {
        let size = viewModel.currentImagePixelSize
        let width = Int(size.width)
        let height = Int(size.height)
        let mb = Double(viewModel.currentImageFileSizeBytes) / 1_048_576.0
        return "\(width)x\(height) | \(String(format: "%.2f", mb)) MB"
    }
}

#Preview {
    ImageViewerWorkspaceView(viewModel: ContentViewModel())
        .padding()
        .background(.ultraThinMaterial)
        .frame(width: 1280, height: 860)
}
