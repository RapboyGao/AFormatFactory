import SwiftUI

struct AppLogCardView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("应用日志")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            ScrollView {
                Text(viewModel.appLogs.isEmpty ? "暂无日志" : viewModel.appLogs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(minHeight: 420)
        }
        .cardStyle(padding: 12)
    }
}
