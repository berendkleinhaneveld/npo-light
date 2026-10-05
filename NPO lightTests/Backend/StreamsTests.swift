//
//  StreamsTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The playback chain up to the licence, held to the captured shapes
/// (ADR 0008, ADR 0009).
struct StreamsTests {
    private static let episode = EpisodeID(rawValue: "7a4c73be-b8e7-4ffd-a2c1-f7df7be3a918")
    private static let playerPath = "/programs/player/7a4c73be-b8e7-4ffd-a2c1-f7df7be3a918"

    private static let protection = StreamProtection(
        certificateURL: URL(filePath: "/certificate/fairplay.cer"),
        licenceURL: URL(filePath: "/authentication"),
        credential: "licence-credential",
        expiresAt: Date(timeIntervalSince1970: 1000)
    )

    /// A signed-in harness whose backend and player host answer from fixtures.
    private static func streams(
        player: HTTPResponse? = nil,
        streamLink: HTTPResponse? = nil
    ) async throws -> (NPOStreams, SignInHarness) {
        let profiles = try Fixture.data("profiles-200")
        let playerResponse = try player ?? HTTPResponse(status: 200, body: Fixture.data("player-200"))
        let linkResponse = try streamLink ?? HTTPResponse(status: 200, body: Fixture.data("stream-link-200"))
        let harness = SignInHarness(backend: { request in
            switch (request.url?.host, request.url?.path) {
            case ("prod.npoplayer.nl", _): linkResponse
            case (_, "/profiles"): HTTPResponse(status: 200, body: profiles)
            case (_, Self.playerPath): playerResponse
            default: .json(SignInHarness.premiumAccount)
            }
        })
        try await harness.signIn()
        let streams = NPOStreams(authenticator: harness.authenticator,
                                 profiles: NPOProfiles(authenticator: harness.authenticator),
                                 transport: harness.transport)
        return (streams, harness)
    }

    @Test("FR-PLAY-11: a stream is the manifest and what the licence exchange needs, as NPO gave them")
    func streamCarriesWhatPlaybackNeeds() async throws {
        let (streams, _) = try await Self.streams()

        let stream = try await streams.stream(for: Self.episode, in: .normal)

        #expect(stream.manifest.absoluteString == "https://npo.prd.cdn.bcms.kpn.com/sanitised/playlist.m3u8")
        #expect(stream.protection?.certificateURL.absoluteString
            == "https://fairplay.npo.nl/certificate/fairplay.cer")
        #expect(stream.protection?.licenceURL.host() == "npo-drm-gateway.samgcloud.nepworldwide.nl")
        #expect(stream.protection?.credential == "sanitised.licence.token")
        #expect(stream.protection?.expiresAt == Date(timeIntervalSince1970: 1_788_209_420))
    }

    @Test("FR-PLAY-11: a stream whose licence address carries its own authorisation has no credential beside it")
    func signedLicenceAddressIsAStream() async throws {
        let link = HTTPResponse(status: 200, body: try Fixture.data("stream-link-signed-address-200"))
        let (streams, _) = try await Self.streams(streamLink: link)

        let stream = try await streams.stream(for: Self.episode, in: .normal)

        #expect(stream.manifest.absoluteString == "https://npo-vod.prd.cdn.bcms.kpn.com/sanitised/index.m3u8")
        #expect(stream.protection?.licenceURL.absoluteString
            == "https://drm.npoplayer.nl/proxyEngine.aspx?auth=sanitised.licence.auth&sig=sanitised-signature")
        #expect(stream.protection?.credential == nil)
        #expect(stream.protection?.expiresAt == Date(timeIntervalSince1970: 1_791_107_859))
    }

    @Test("FR-PLAY-11: a stream NPO sends in the clear is a manifest with nothing to exchange")
    func unprotectedStreamIsPlayable() async throws {
        let body = #"{"stream":{"streamURL":"https://cdn.example/clear/index.m3u8","drm":null,"avType":"vod"}}"#
        let (streams, _) = try await Self.streams(streamLink: HTTPResponse(status: 200, body: Data(body.utf8)))

        let stream = try await streams.stream(for: Self.episode, in: .normal)

        #expect(stream.manifest.absoluteString == "https://cdn.example/clear/index.m3u8")
        #expect(stream.protection == nil)
    }

    @Test("FR-PLAY-10: protection that cannot be read is an error, not a stream to play without it")
    func unreadableProtectionIsRefused() async throws {
        let body = #"""
        {"stream":{"streamURL":"https://cdn.example/index.m3u8",
                   "drm":{"certificateUrl":"","licenseUrl":"https://licence.example/"}}}
        """#
        let (streams, _) = try await Self.streams(streamLink: HTTPResponse(status: 200, body: Data(body.utf8)))

        await #expect(throws: BackendError.self) {
            _ = try await streams.stream(for: Self.episode, in: .normal)
        }
    }

    @Test("FR-PLAY-11, FR-MODE-04: the player token is asked for as the mode's profile, then exchanged raw")
    func tokenIsExchangedRaw() async throws {
        let (streams, harness) = try await Self.streams()

        _ = try await streams.stream(for: Self.episode, in: .kids)

        let player = try #require(harness.backendRequests.first { $0.url?.path == Self.playerPath })
        #expect(player.url?.query() == "player-environment=production")
        #expect(player.value(forHTTPHeaderField: "profile-guid") == "00000000-0000-0000-0000-000000000012")
        #expect(player.value(forHTTPHeaderField: "Authorization") == "Bearer id-token-1")
        let link = try #require(harness.backendRequests.last)
        #expect(link.url?.absoluteString == "https://prod.npoplayer.nl/stream-link")
        #expect(link.httpMethod == "POST")
        // The raw token: with a Bearer prefix the player host refuses it.
        #expect(link.value(forHTTPHeaderField: "Authorization") == "sanitised.player.token")
        let body = try JSONSerialization.jsonObject(with: try #require(link.httpBody)) as? [String: Any]
        #expect(body?["profileName"] as? String == "hls")
        #expect(body?["drmType"] as? String == "fairplay")
    }

    @Test("FR-PLAY-11: every playback obtains its own stream details")
    func nothingIsReused() async throws {
        let (streams, harness) = try await Self.streams()

        _ = try await streams.stream(for: Self.episode, in: .normal)
        _ = try await streams.stream(for: Self.episode, in: .normal)

        #expect(harness.backendRequests.filter { $0.url?.path == Self.playerPath }.count == 2)
        #expect(harness.backendRequests.filter { $0.url?.host == "prod.npoplayer.nl" }.count == 2)
    }

    @Test("FR-CONTENT-05, FR-PLAY-10: an item NPO no longer has is unavailable, and no stream is asked for")
    func goneItemIsUnavailable() async throws {
        let (streams, harness) = try await Self.streams(player: .json("{}", status: 404))

        await #expect(throws: BackendError.itemUnavailable) {
            _ = try await streams.stream(for: Self.episode, in: .normal)
        }
        #expect(!harness.backendRequests.contains { $0.url?.host == "prod.npoplayer.nl" })
    }

    @Test("FR-PLAY-10: a stream the player host refuses is an error, not a crash or a half-read answer", arguments: [
        HTTPResponse.json(#"{"message":"Autorisatie van de speler mislukt","code":401}"#, status: 403),
        HTTPResponse.json(#"{"stream":{"streamURL":"https://example.invalid/a.m3u8"}}"#)
    ])
    func refusedStreamIsAnError(response: HTTPResponse) async throws {
        let (streams, _) = try await Self.streams(streamLink: response)

        await #expect(throws: BackendError.unexpectedResponse(status: response.status)) {
            _ = try await streams.stream(for: Self.episode, in: .normal)
        }
    }

    @Test("FR-AUTH-05: the advertisement fields a stream answer carries are not followed")
    func advertisementFieldsAreIgnored() async throws {
        let withPreroll = """
        {"stream":{"streamURL":"https://cdn.example.invalid/playlist.m3u8",
        "drm":{"certificateUrl":"https://fairplay.npo.nl/certificate/fairplay.cer",
        "licenseUrl":"https://licence.example.invalid/authentication",
        "httpHeaders":{"X-Custom-Data":"credential"}}},
        "assets":{"preroll":"https://ads.example.invalid/preroll.xml"},
        "metadata":{"hasPreroll":"true"}}
        """
        let (streams, harness) = try await Self.streams(streamLink: .json(withPreroll))

        let stream = try await streams.stream(for: Self.episode, in: .normal)

        #expect(stream.manifest.host() == "cdn.example.invalid")
        #expect(!harness.transport.sent.contains { $0.url?.host == "ads.example.invalid" })
    }

    #if targetEnvironment(simulator)
    @Test("FR-PLAY-10: on a simulator, which has no FairPlay, playback fails as an error and asks NPO for nothing")
    @MainActor
    func simulatorCannotPlayProtectedStreams() async throws {
        let (streams, harness) = try await Self.streams()
        let asked = harness.transport.sent.count
        let playback = NPOPlayback(streams: streams,
                                   licenser: FairPlayLicenser(transport: harness.transport),
                                   clock: TestClock())
        let episode = Playable(id: Self.episode, title: "", caption: nil, synopsis: nil, duration: nil, artwork: nil)

        await #expect(throws: BackendError.protectionUnsupported) {
            _ = try await playback.playback(of: episode, in: .normal)
        }

        #expect(harness.transport.sent.count == asked)
    }
    #endif

    // MARK: the licence exchange

    @Test("FR-PLAY-11: the licence request carries the system's key request raw, with NPO's credential")
    func licenceRequestIsForwardedRaw() async throws {
        let keyRequest = Data([0x01, 0x02, 0x03])
        let licence = Data([0xAA, 0xBB])
        // The gateway labels its answer as HTML; the bytes are the licence.
        let transport = StubTransport { _ in
            HTTPResponse(status: 200, headers: ["content-type": "text/html; charset=ISO-8859-1"], body: licence)
        }

        let answer = try await FairPlayLicenser(transport: transport)
            .licence(for: keyRequest, assetID: "929b1e40-e233", protection: Self.protection)

        #expect(answer == licence)
        let request = try #require(transport.sent.first)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == keyRequest)
        #expect(request.url?.query() == "assetId=929b1e40-e233")
        #expect(request.value(forHTTPHeaderField: "X-Custom-Data") == "licence-credential")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("FR-PLAY-11: a licence address that carries its own authorisation is used exactly as NPO gave it")
    func signedLicenceAddressIsLeftAlone() async throws {
        let address = try #require(URL(string: "https://drm.npoplayer.nl/proxyEngine.aspx?auth=a.b.c&sig=d"))
        let signed = StreamProtection(certificateURL: Self.protection.certificateURL,
                                      licenceURL: address,
                                      credential: nil,
                                      expiresAt: nil)
        let keyRequest = Data([0x01, 0x02, 0x03])
        let transport = StubTransport { _ in HTTPResponse(status: 200, body: Data([0xAA])) }

        _ = try await FairPlayLicenser(transport: transport)
            .licence(for: keyRequest, assetID: "929b1e40-e233", protection: signed)

        let request = try #require(transport.sent.first)
        #expect(request.url == address)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == keyRequest)
        #expect(request.value(forHTTPHeaderField: "X-Custom-Data") == nil)
    }

    @Test("FR-PLAY-10, FR-PLAY-11: a licence the gateway refuses is an error the player can retry")
    func refusedLicenceIsAnError() async throws {
        let licenser = FairPlayLicenser(transport: StubTransport { _ in .json("{}", status: 403) })

        await #expect(throws: BackendError.unexpectedResponse(status: 403)) {
            _ = try await licenser.licence(for: Data([0x01]), assetID: "asset", protection: Self.protection)
        }
    }

    @Test("FR-PLAY-11: the certificate is asked for without any credential")
    func certificateNeedsNoCredential() async throws {
        let certificate = Data([0x30, 0x82])
        let transport = StubTransport { _ in HTTPResponse(status: 200, body: certificate) }

        let answer = try await FairPlayLicenser(transport: transport).certificate(for: Self.protection)

        #expect(answer == certificate)
        #expect(transport.sent.first?.allHTTPHeaderFields?.isEmpty != false)
    }

    @Test("FR-PLAY-11: the asset a key is for is the bare identifier, without its scheme", arguments: [
        ("skd://929b1e40-e233-7c22-965f-f14769d187d8", "929b1e40-e233-7c22-965f-f14769d187d8"),
        ("skd://", nil),
        ("https://example.invalid/key", nil)
    ] as [(String, String?)])
    func assetIdentifierIsBare(identifier: String, asset: String?) {
        #expect(FairPlayLicenser.assetID(fromKeyIdentifier: identifier) == asset)
    }

    @Test("FR-PLAY-11: a renewal, or a lapsed credential, gets fresh stream details")
    func lapsedCredentialIsNotReused() {
        let before = Date(timeIntervalSince1970: 999)
        let after = Date(timeIntervalSince1970: 1000)
        let undated = StreamProtection(certificateURL: Self.protection.certificateURL,
                                       licenceURL: Self.protection.licenceURL,
                                       credential: "credential",
                                       expiresAt: nil)

        #expect(FairPlayLicenser.isUsable(Self.protection, at: before, forRenewal: false))
        #expect(!FairPlayLicenser.isUsable(Self.protection, at: after, forRenewal: false))
        #expect(!FairPlayLicenser.isUsable(Self.protection, at: before, forRenewal: true))
        #expect(FairPlayLicenser.isUsable(undated, at: after, forRenewal: false))
    }
}
