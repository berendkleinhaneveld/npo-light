//
//  SignInPresentationTests.swift
//  NPO lightTests
//

import CoreImage
import Foundation
import Testing
@testable import NPO_light

struct SignInPresentationTests {
    private static let complete = "https://id.npo.nl/koppel?userCode=51411921"

    /// What a scanner reads from `image`, with the quiet zone a screen gives it.
    private static func scanned(_ image: CGImage) -> [String] {
        let code = CIImage(cgImage: image)
        let margin: CGFloat = 48
        let ground = CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -margin, dy: -margin))
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: code.composited(over: ground)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    @Test("FR-AUTH-06: the QR code is made on the device and reads back as the complete address")
    func codeScansAsTheCompleteAddress() throws {
        let image = try #require(QRCode.image(encoding: Self.complete))

        #expect(image.width == image.height)
        #expect(Self.scanned(image) == [Self.complete])
    }

    @Test("FR-AUTH-06: a different code gives a different QR code")
    func codeFollowsItsContent() throws {
        let image = try #require(QRCode.image(encoding: "https://id.npo.nl/koppel?userCode=20261002"))

        #expect(Self.scanned(image) == ["https://id.npo.nl/koppel?userCode=20261002"])
    }

    @Test("FR-AUTH-06: the address shown as text is the short one, without its scheme")
    func addressIsShownShort() throws {
        let url = try #require(URL(string: "https://id.npo.nl/koppel"))

        #expect(SignInChallengeView.displayed(url) == "id.npo.nl/koppel")
    }

    @Test("FR-AUTH-06: the code is shown in groups a person can read out", arguments: [
        ("51411921", "5141 1921"),
        ("514119", "5141 19"),
        ("", "")
    ])
    func codeIsGrouped(code: String, shown: String) {
        #expect(SignInChallengeView.grouped(code) == shown)
    }
}
