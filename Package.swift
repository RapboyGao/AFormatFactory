// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AFormatFactory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AFormatFactory", targets: ["AFormatFactoryApp"])
    ],
    targets: [
        .executableTarget(
            name: "AFormatFactoryApp",
            path: "Sources/AFormatFactoryApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist so `swift run` has a main bundle identifier.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AFormatFactoryApp/Info.plist"
                ])
            ]
        )
    ]
)
