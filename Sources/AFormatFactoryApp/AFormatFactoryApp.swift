import SwiftUI
import AFormatFactoryUI

@main
struct AFormatFactoryApp: App {
    @StateObject private var viewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowResizability(.contentMinSize)

        WindowGroup(id: AppWindowID.previewEditor) {
            PreviewEditorWindowView(viewModel: viewModel)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowResizability(.contentMinSize)
    }
}
