//
//  TestCard.swift
//  NPO light
//

#if DEBUG
import AVFoundation
import CoreGraphics
import CoreText
import Foundation

/// A video made on the spot: three minutes of a dark screen with the time
/// written on it, one frame a second (ADR 0019).
///
/// NPO's streams are protected and the simulator cannot play a protected
/// stream at all. This stands in for one there, so that everything around the
/// player — resuming, the position being written, the finish — can be seen
/// and tested. The time in the picture is what makes a resume visible.
/// Debug builds only: nothing here is in the app that ships.
nonisolated enum TestCard {
    struct NotMade: Error {}

    /// Long enough to stop halfway, short enough to watch to the end: at
    /// three minutes the completion threshold falls at 2:51 (FR-PLAY-04).
    static let duration = 180

    private static let width = 640
    private static let height = 360

    /// The file, made now if this launch has not made it yet.
    @concurrent
    static func video() async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appending(path: "npo-light-test-card-\(duration).mp4")
        if FileManager.default.fileExists(atPath: url.path()) { return url }
        // Written under a name of its own and moved into place, so that a
        // second player asking meanwhile never opens half a file.
        let draft = directory.appending(path: "npo-light-test-card-\(UUID().uuidString).mp4")
        try await write(to: draft)
        do {
            try FileManager.default.moveItem(at: draft, to: url)
        } catch {
            // Somebody else got there first, and theirs is as good.
            try? FileManager.default.removeItem(at: draft)
        }
        return url
    }

    private static func write(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NotMade() }
        writer.startSession(atSourceTime: .zero)
        for second in 0..<duration {
            while !input.isReadyForMoreMediaData {
                await Task.yield()
            }
            guard let pool = adaptor.pixelBufferPool else { throw NotMade() }
            let frame = try frame(for: second, from: pool)
            guard adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(second), timescale: 1)) else {
                throw writer.error ?? NotMade()
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(duration), timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NotMade() }
    }

    /// One frame: the time, and a bar that is as far along as the video is.
    private static func frame(for second: Int, from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw NotMade() }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let layout = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: layout) else { throw NotMade() }
        context.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0.42, blue: 0, alpha: 1))
        let played = CGFloat(width) * CGFloat(second) / CGFloat(duration)
        context.fill(CGRect(x: 0, y: 0, width: played, height: 24))

        let text = String(format: "%d:%02d", second / 60, second % 60)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 120, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: (CGFloat(height) - bounds.height) / 2)
        CTLineDraw(line, context)
        return buffer
    }
}
#endif
