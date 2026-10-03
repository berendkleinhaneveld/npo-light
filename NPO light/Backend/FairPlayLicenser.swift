//
//  FairPlayLicenser.swift
//  NPO light
//

import Foundation

/// The two requests of a FairPlay licence exchange.
///
/// The app decrypts nothing and holds no key: the operating system makes the
/// key request and consumes the answer, and this only carries them to NPO's
/// licence gateway and back (FR-PLAY-11).
nonisolated struct FairPlayLicenser: Sendable {
    private let transport: any HTTPTransport

    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// NPO's FairPlay application certificate. Public, and asked for without
    /// any credential.
    func certificate(for protection: StreamProtection) async throws -> Data {
        let response = try await transport.reaching(URLRequest(url: protection.certificateURL))
        guard response.status == 200, !response.body.isEmpty else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        return response.body
    }

    /// Exchanges the system's key request for a licence.
    ///
    /// The answer is the licence's raw bytes whatever its `Content-Type` says —
    /// the gateway labels it as HTML.
    func licence(for keyRequest: Data, assetID: String, protection: StreamProtection) async throws -> Data {
        let response = try await transport.reaching(
            NPOWire.licenceRequest(keyRequest: keyRequest, assetID: assetID, protection: protection)
        )
        guard response.status == 200, !response.body.isEmpty else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        return response.body
    }

    /// The asset a key is for: the identifier in the stream is `skd://<uuid>`,
    /// and the gateway wants the bare `<uuid>`.
    static func assetID(fromKeyIdentifier identifier: String) -> String? {
        let scheme = "skd://"
        guard identifier.hasPrefix(scheme) else { return nil }
        let asset = String(identifier.dropFirst(scheme.count))
        return asset.isEmpty ? nil : asset
    }

    /// Whether `protection` can still be used for a licence at `now`.
    ///
    /// A renewal during a long playback never can: the credential lived about
    /// a minute, so fresh stream details are fetched instead.
    static func isUsable(_ protection: StreamProtection, at now: Date, forRenewal: Bool) -> Bool {
        guard !forRenewal else { return false }
        guard let expiresAt = protection.expiresAt else { return true }
        return now < expiresAt
    }
}
