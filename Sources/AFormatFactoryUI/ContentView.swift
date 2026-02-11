import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AFormatFactory")
                .font(.largeTitle)
                .bold()

            Picker("功能区", selection: $viewModel.domain) {
                ForEach(ConversionDomain.allCases) { domain in
                    Text(domain.displayName).tag(domain)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button("选择输入文件") {
                    viewModel.pickInputFiles()
                }

                Button("选择输出目录") {
                    viewModel.pickOutputDirectory()
                }

                Picker("输出格式", selection: $viewModel.format) {
                    ForEach(viewModel.availableFormats) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Button(viewModel.isConverting ? "转换中..." : "开始转换") {
                    Task {
                        await viewModel.startConversion()
                    }
                }
                .disabled(viewModel.isConverting)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.domain.displayName) 输入文件（\(viewModel.selectedFiles.count)）")
                    .font(.headline)
                List(viewModel.selectedFiles, id: \.self) { url in
                    Text(url.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                .frame(height: 170)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("输出目录")
                    .font(.headline)
                Text(viewModel.outputDirectory?.path ?? "未选择")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("日志")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.logs.isEmpty ? "暂无日志" : viewModel.logs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
                .cornerRadius(8)
            }
        }
        .padding(20)
    }
}

#Preview {
    ContentView()
        .frame(width: 860, height: 560)
}
