// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AFormatFactory",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AFormatFactoryUI", targets: ["AFormatFactoryUI"]),
        .library(name: "AFormatFactoryFFmpegKit", targets: ["AFormatFactoryFFmpegKit"]),
        .executable(name: "AFormatFactory", targets: ["AFormatFactoryApp"])
    ],
    targets: [
        .target(
            name: "AFormatFactoryFFmpegC",
            path: "Sources/AFormatFactoryFFmpegC",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-IThirdParty/ffmpeg-install/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-LThirdParty/ffmpeg-install/lib"]),
                .linkedLibrary("avformat"),
                .linkedLibrary("avcodec"),
                .linkedLibrary("avfilter"),
                .linkedLibrary("swresample"),
                .linkedLibrary("swscale"),
                .linkedLibrary("avutil"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("m"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("AppKit"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "AFormatFactoryFFmpegKit",
            dependencies: ["AFormatFactoryFFmpegC"],
            path: "Sources/AFormatFactoryFFmpegKit"
        ),
        .target(
            name: "AFormatFactoryUI",
            dependencies: ["AFormatFactoryFFmpegKit"],
            path: "Sources/AFormatFactoryUI"
        ),
        .executableTarget(
            name: "AFormatFactoryApp",
            dependencies: ["AFormatFactoryUI"],
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
        ),
        .testTarget(
            name: "AFormatFactoryFFmpegKitTests",
            dependencies: ["AFormatFactoryFFmpegKit"],
            path: "Tests/AFormatFactoryFFmpegKitTests"
        )
    ]
)
