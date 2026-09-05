// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ScreenCaptureKit
import CoreImage
import UniformTypeIdentifiers

final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "ScreenTask.capture", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let quality: Double
    private let output: (Data) -> Void
    private let failure: (Error) -> Void
    init(quality: Double, output: @escaping (Data) -> Void, failure: @escaping (Error) -> Void) {
        self.quality = quality; self.output = output; self.failure = failure
    }
    func start(display: SCDisplay, interval: Int, cursor: Bool, maxWidth: Int) async throws {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = min(1.0, Double(maxWidth) / Double(display.width))
        config.width = max(2, Int(Double(display.width) * scale))
        config.height = max(2, Int(Double(display.height) * scale))
        config.minimumFrameInterval = CMTime(value: CMTimeValue(interval), timescale: 1000)
        config.showsCursor = cursor
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }
    func stop() async { try? await stream?.stopCapture(); stream = nil }
    func stream(_ stream: SCStream, didStopWithError error: Error) { failure(error) }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: buffer)
            if let jpeg = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]) {
                output(jpeg)
            }
        }
    }
}
