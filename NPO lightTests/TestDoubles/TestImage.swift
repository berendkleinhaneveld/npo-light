//
//  TestImage.swift
//  NPO lightTests
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images made on the spot, so that no test depends on one of NPO's.
nonisolated enum TestImage {
    struct NotDrawn: Error {}

    /// A plain image of this many pixels.
    static func image(width: Int, height: Int) throws -> CGImage {
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let image = context?.makeImage() else { throw NotDrawn() }
        return image
    }

    /// The same, as the bytes of a PNG file.
    static func png(width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        let type = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { throw NotDrawn() }
        CGImageDestinationAddImage(destination, try image(width: width, height: height), nil)
        guard CGImageDestinationFinalize(destination) else { throw NotDrawn() }
        return data as Data
    }
}
