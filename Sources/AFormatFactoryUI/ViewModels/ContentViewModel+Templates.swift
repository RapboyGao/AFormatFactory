import AppKit
import Foundation

private struct ParameterTemplate: Codable {
    let conversionPreset: ConversionPreset

    let copyVideoStream: Bool
    let videoRateControl: VideoRateControl
    let videoEncoder: VideoEncoderOption
    let videoScalePreset: VideoScalePreset
    let videoPreset: VideoPresetOption
    let videoPixelFormat: String
    let videoGOP: String
    let videoProfile: String
    let videoLevel: String
    let videoTune: String
    let videoCRF: Double
    let videoBitrateKbps: String
    let videoMaxBitrateKbps: String
    let videoBufferSizeKbps: String
    let videoFrameRate: String
    let enableDeinterlace: Bool
    let videoRotate: VideoRotateOption
    let videoFlipHorizontal: Bool
    let videoFlipVertical: Bool
    let videoCropWidth: String
    let videoCropHeight: String
    let videoCropX: String
    let videoCropY: String

    let copyAudioStream: Bool
    let audioCodec: AudioCodecOption
    let audioBitrateKbps: String
    let audioSampleRate: String
    let audioChannels: Int
    let audioVolumeDB: String
    let audioVBRQuality: String
    let enableLoudnorm: Bool
    let loudnormIntegratedTarget: String
    let loudnormLraTarget: String
    let loudnormTruePeakTarget: String
    let selectedAudioTrackIndex: String

    let keepMetadata: Bool
    let enableFastStart: Bool
    let startTime: String
    let duration: String
    let threadCount: String
    let customFFmpegArgs: String
}

extension ContentViewModel {
    func saveParameterTemplate() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AFormatFactory-Template.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let template = currentTemplate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(template)
            try data.write(to: url, options: .atomic)
            appendAppLog("参数模板已保存：\(url.path)")
        } catch {
            appendAppLog("保存参数模板失败：\(error.localizedDescription)")
        }
    }

    func loadParameterTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let template = try decoder.decode(ParameterTemplate.self, from: data)
            applyTemplate(template)
            appendAppLog("参数模板已加载：\(url.path)")
        } catch {
            appendAppLog("加载参数模板失败：\(error.localizedDescription)")
        }
    }

    private func currentTemplate() -> ParameterTemplate {
        ParameterTemplate(
            conversionPreset: conversionPreset,
            copyVideoStream: copyVideoStream,
            videoRateControl: videoRateControl,
            videoEncoder: videoEncoder,
            videoScalePreset: videoScalePreset,
            videoPreset: videoPreset,
            videoPixelFormat: videoPixelFormat,
            videoGOP: videoGOP,
            videoProfile: videoProfile,
            videoLevel: videoLevel,
            videoTune: videoTune,
            videoCRF: videoCRF,
            videoBitrateKbps: videoBitrateKbps,
            videoMaxBitrateKbps: videoMaxBitrateKbps,
            videoBufferSizeKbps: videoBufferSizeKbps,
            videoFrameRate: videoFrameRate,
            enableDeinterlace: enableDeinterlace,
            videoRotate: videoRotate,
            videoFlipHorizontal: videoFlipHorizontal,
            videoFlipVertical: videoFlipVertical,
            videoCropWidth: videoCropWidth,
            videoCropHeight: videoCropHeight,
            videoCropX: videoCropX,
            videoCropY: videoCropY,
            copyAudioStream: copyAudioStream,
            audioCodec: audioCodec,
            audioBitrateKbps: audioBitrateKbps,
            audioSampleRate: audioSampleRate,
            audioChannels: audioChannels,
            audioVolumeDB: audioVolumeDB,
            audioVBRQuality: audioVBRQuality,
            enableLoudnorm: enableLoudnorm,
            loudnormIntegratedTarget: loudnormIntegratedTarget,
            loudnormLraTarget: loudnormLraTarget,
            loudnormTruePeakTarget: loudnormTruePeakTarget,
            selectedAudioTrackIndex: selectedAudioTrackIndex,
            keepMetadata: keepMetadata,
            enableFastStart: enableFastStart,
            startTime: startTime,
            duration: duration,
            threadCount: threadCount,
            customFFmpegArgs: customFFmpegArgs
        )
    }

    private func applyTemplate(_ template: ParameterTemplate) {
        conversionPreset = template.conversionPreset

        copyVideoStream = template.copyVideoStream
        videoRateControl = template.videoRateControl
        videoEncoder = template.videoEncoder
        videoScalePreset = template.videoScalePreset
        videoPreset = template.videoPreset
        videoPixelFormat = template.videoPixelFormat
        videoGOP = template.videoGOP
        videoProfile = template.videoProfile
        videoLevel = template.videoLevel
        videoTune = template.videoTune
        videoCRF = template.videoCRF
        videoBitrateKbps = template.videoBitrateKbps
        videoMaxBitrateKbps = template.videoMaxBitrateKbps
        videoBufferSizeKbps = template.videoBufferSizeKbps
        videoFrameRate = template.videoFrameRate
        enableDeinterlace = template.enableDeinterlace
        videoRotate = template.videoRotate
        videoFlipHorizontal = template.videoFlipHorizontal
        videoFlipVertical = template.videoFlipVertical
        videoCropWidth = template.videoCropWidth
        videoCropHeight = template.videoCropHeight
        videoCropX = template.videoCropX
        videoCropY = template.videoCropY

        copyAudioStream = template.copyAudioStream
        audioCodec = template.audioCodec
        audioBitrateKbps = template.audioBitrateKbps
        audioSampleRate = template.audioSampleRate
        audioChannels = template.audioChannels
        audioVolumeDB = template.audioVolumeDB
        audioVBRQuality = template.audioVBRQuality
        enableLoudnorm = template.enableLoudnorm
        loudnormIntegratedTarget = template.loudnormIntegratedTarget
        loudnormLraTarget = template.loudnormLraTarget
        loudnormTruePeakTarget = template.loudnormTruePeakTarget
        selectedAudioTrackIndex = template.selectedAudioTrackIndex

        keepMetadata = template.keepMetadata
        enableFastStart = template.enableFastStart
        startTime = template.startTime
        duration = template.duration
        threadCount = template.threadCount
        customFFmpegArgs = template.customFFmpegArgs

        if !availableVideoEncoders.contains(videoEncoder) {
            videoEncoder = .auto
        }
    }
}
