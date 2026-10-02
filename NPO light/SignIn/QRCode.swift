//
//  QRCode.swift
//  NPO light
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// A QR code, drawn on the device (FR-AUTH-06).
///
/// Core Image generates it locally: no image is fetched, and what is encoded is
/// sent to no host to render it (NFR-PRIV-03).
nonisolated enum QRCode {
    /// Pixels per module. Enough that scaling it up on screen stays sharp
    /// without interpolation doing the work.
    private static let scale: CGFloat = 12

    /// Dark modules on a light ground, with no quiet zone around them: the
    /// view supplies that.
    static func image(encoding text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
