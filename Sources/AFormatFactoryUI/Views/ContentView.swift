import AppKit
import SwiftUI

public enum AppWindowID {
    public static let previewEditor = "preview-editor"
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case videoConvert
    case audioConvert
    case mediaEdit
    case imageViewer
    case tasks
    case appLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videoConvert:
            return "视频格式转换"
        case .audioConvert:
            return "音频格式转换"
        case .mediaEdit:
            return "媒体编辑"
        case .imageViewer:
            return "图片查看器"
        case .tasks:
            return "任务队列"
        case .appLog:
            return "应用日志"
        }
    }

    var symbol: String {
        switch self {
        case .videoConvert:
            return "film.stack"
        case .audioConvert:
            return "waveform"
        case .mediaEdit:
            return "wand.and.stars"
        case .imageViewer:
            return "photo.stack"
        case .tasks:
            return "list.bullet.rectangle"
        case .appLog:
            return "doc.text.magnifyingglass"
        }
    }
}

@MainActor
public struct ContentView: View {
    @ObservedObject private var viewModel: ContentViewModel
    @State private var selectedSection: WorkspaceSection? = .videoConvert

    public init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            NavigationSplitView {
                WorkspaceSidebarView(viewModel: viewModel, selectedSection: $selectedSection)
            } detail: {
                ScrollView {
                    VStack(spacing: 12) {
                        switch selectedSection ?? .videoConvert {
                        case .videoConvert:
                            ConversionWorkspaceView(viewModel: viewModel, selectedSection: $selectedSection, targetDomain: .video)
                        case .audioConvert:
                            ConversionWorkspaceView(viewModel: viewModel, selectedSection: $selectedSection, targetDomain: .audio)
                        case .mediaEdit:
                            MediaEditWorkspaceView(viewModel: viewModel)
                        case .imageViewer:
                            ImageViewerWorkspaceView(viewModel: viewModel)
                        case .tasks:
                            TaskWorkspaceView(viewModel: viewModel)
                        case .appLog:
                            AppLogCardView(viewModel: viewModel)
                        }
                    }
                    .padding(14)
                }
                .background(backgroundLayer)
            }

            if viewModel.imageFullscreenPresented {
                ImageFullscreenOverlayView(viewModel: viewModel)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.shutdownAndCleanup()
        }
    }

    private var backgroundLayer: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView(viewModel: ContentViewModel())
        .frame(width: 1200, height: 860)
}
