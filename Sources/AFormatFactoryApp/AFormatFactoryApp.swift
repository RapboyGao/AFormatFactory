import SwiftUI
import AFormatFactoryUI

@main
struct AFormatFactoryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
