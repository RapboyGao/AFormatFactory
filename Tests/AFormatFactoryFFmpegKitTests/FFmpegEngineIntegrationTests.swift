import AVFoundation
import CoreVideo
import Foundation
import XCTest
@testable import AFormatFactoryFFmpegKit

final class LogStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func all() -> [String] {
        lock.lock()
        let snapshot = values
        lock.unlock()
        return snapshot
    }
}

final class FFmpegEngineIntegrationTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aformatfactory-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeSineWaveWAV(to url: URL, duration: Double = 1.0, sampleRate: Double = 44_100) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to allocate audio buffer"])
        }
        buffer.frameLength = frameCount
        let frequency = 440.0
        let amplitude: Float = 0.2
        guard let channel = buffer.floatChannelData?[0] else {
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing channel data"])
        }
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            channel[i] = amplitude * Float(sin(2.0 * .pi * frequency * t))
        }
        try file.write(from: buffer)
    }

    private func writeSolidColorVideo(to url: URL, duration: Double = 1.0, fps: Int32 = 30, size: CGSize = CGSize(width: 320, height: 180)) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourceAttributes)

        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)

        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(duration * Double(fps))
        let frameDuration = CMTime(value: 1, timescale: fps)

        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "missing pixel buffer pool"])
            }
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let pixelBuffer else {
                throw NSError(domain: "test", code: 4, userInfo: [NSLocalizedDescriptionKey: "failed creating pixel buffer"])
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                memset(base, Int32(0x22 + (index % 16)), bytesPerRow * height)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(index))
            _ = adaptor.append(pixelBuffer, withPresentationTime: pts)
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "test", code: 5, userInfo: [NSLocalizedDescriptionKey: "video writer failed"])
        }
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    private func runJob(engine: FFmpegEngine, job: FFmpegJob) async throws {
        _ = try await engine.execute(
            job: job,
            callbacks: FFmpegCallbacks(
                onLog: { _, _ in },
                onProgress: { _ in },
                onState: { _ in }
            )
        )
    }

    private func runJobCollectingLogs(engine: FFmpegEngine, job: FFmpegJob) async throws -> [String] {
        let logStore = LogStore()
        _ = try await engine.execute(
            job: job,
            callbacks: FFmpegCallbacks(
                onLog: { _, message in
                    logStore.append(message)
                },
                onProgress: { _ in },
                onState: { _ in }
            )
        )
        return logStore.all()
    }

    func testAudioTranscodeWithAF() async throws {
        let dir = try makeTempDirectory()
        let input = dir.appendingPathComponent("input.wav")
        let output = dir.appendingPathComponent("output.wav")
        try writeSineWaveWAV(to: input)

        let engine = FFmpegEngine()
        let job = FFmpegJob(
            id: UUID(),
            input: input,
            output: output,
            overwriteExisting: true,
            arguments: ["-c:a", "pcm_s16le", "-af", "volume=3.0"]
        )

        try await runJob(engine: engine, job: job)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertGreaterThan(try fileSize(output), 0)

        let info = try await engine.probe(url: output)
        XCTAssertGreaterThanOrEqual(info.streamCount, 1)
    }

    func testVideoTranscodeWithVF() async throws {
        let dir = try makeTempDirectory()
        let input = dir.appendingPathComponent("input.mov")
        let output = dir.appendingPathComponent("output.mp4")
        try await writeSolidColorVideo(to: input)

        let engine = FFmpegEngine()
        let job = FFmpegJob(
            id: UUID(),
            input: input,
            output: output,
            overwriteExisting: true,
            arguments: ["-c:v", "mpeg4", "-b:v", "1200k", "-vf", "scale=160:90", "-an"]
        )

        try await runJob(engine: engine, job: job)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertGreaterThan(try fileSize(output), 0)

        let info = try await engine.probe(url: output)
        XCTAssertGreaterThanOrEqual(info.streamCount, 1)
    }

    func testMediaEditWithMetadataChapterAudioAndSubtitle() async throws {
        let dir = try makeTempDirectory()
        let inputVideo = dir.appendingPathComponent("input.mov")
        let extraAudio = dir.appendingPathComponent("extra.wav")
        let subtitle = dir.appendingPathComponent("sub.srt")
        let output = dir.appendingPathComponent("edited.mkv")

        try await writeSolidColorVideo(to: inputVideo)
        try writeSineWaveWAV(to: extraAudio)
        let srt = """
        1
        00:00:00,000 --> 00:00:00,900
        hello
        """
        try srt.write(to: subtitle, atomically: true, encoding: .utf8)

        let engine = FFmpegEngine()
        let mediaEdit = FFmpegMediaEditConfig(
            additionalAudioInput: extraAudio,
            subtitleInput: subtitle,
            subtitleCodec: "copy",
            metadata: ["title": "IntegrationTest", "artist": "AFormatFactory"],
            chapters: [
                FFmpegMediaEditChapter(startMilliseconds: 0, endMilliseconds: 800, title: "Intro")
            ]
        )
        let job = FFmpegJob(
            id: UUID(),
            input: inputVideo,
            output: output,
            overwriteExisting: true,
            arguments: [],
            mediaEditConfig: mediaEdit
        )

        try await runJob(engine: engine, job: job)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertGreaterThan(try fileSize(output), 0)

        let info = try await engine.probe(url: output)
        XCTAssertGreaterThanOrEqual(info.streamCount, 2)
    }

    func testDefaultLikeVideoArgumentsProduceNoUnsupportedWarnings() async throws {
        let dir = try makeTempDirectory()
        let input = dir.appendingPathComponent("input.mov")
        let output = dir.appendingPathComponent("output.mp4")
        try await writeSolidColorVideo(to: input)

        let engine = FFmpegEngine()
        let args = [
            "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "192k",
            "-preset", "medium", "-pix_fmt", "yuv420p", "-crf", "23",
            "-b:a", "192k", "-ar", "44100", "-ac", "2",
            "-movflags", "+faststart"
        ]
        let job = FFmpegJob(
            id: UUID(),
            input: input,
            output: output,
            overwriteExisting: true,
            arguments: args
        )

        let logs = try await runJobCollectingLogs(engine: engine, job: job)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(logs.contains(where: { $0.contains("ignore unsupported option") }))
    }
}
