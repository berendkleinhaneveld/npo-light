//
//  SubtitledManifestTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// NPO's subtitles, added to the stream so that the system player offers
/// them (ADR 0027).
struct SubtitledManifestTests {
    private static let base = URL(filePath: "/signed/prid/stream.m3u8")
    private static let dutch = SubtitleTrack(language: "nl",
                                             name: "Nederlands",
                                             location: URL(filePath: "/subtitles/nl/prid.vtt"))

    /// The shape of NPO's manifest: keys, one group of sound, variants, and
    /// everything named relative to the manifest itself.
    private static let original = """
    #EXTM3U
    #EXT-X-VERSION:4
    #EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://key-1",KEYFORMAT="com.apple.streamingkeydelivery"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",LANGUAGE="und",NAME="Undetermined",DEFAULT=YES,URI="audio/sound.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=378001,RESOLUTION=320x180,AUDIO="aud1"
    video/low.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=5870001,RESOLUTION=1920x1080,AUDIO="aud1"
    video/high.m3u8
    """

    private static func lines(adding tracks: [SubtitleTrack] = [dutch]) -> [String] {
        SubtitledManifest.multivariant(original, from: base, adding: tracks)
            .split(separator: "\n")
            .map(String.init)
    }

    @Test("FR-PLAY-01: the subtitles NPO has are named in the manifest, once, before the variants")
    func subtitlesAreNamed() throws {
        let lines = Self.lines()

        let renditions = lines.filter { $0.contains("TYPE=SUBTITLES") }
        let rendition = try #require(renditions.first)
        #expect(renditions.count == 1)
        #expect(rendition.contains("LANGUAGE=\"nl\""))
        #expect(rendition.contains("NAME=\"Nederlands\""))
        // Offered, not switched on: whether subtitles show is the viewer's
        // setting.
        #expect(rendition.contains("DEFAULT=NO"))
        let firstVariant = try #require(lines.firstIndex { $0.hasPrefix("#EXT-X-STREAM-INF") })
        #expect(try #require(lines.firstIndex(of: rendition)) < firstVariant)
    }

    @Test("FR-PLAY-01: every variant of the picture carries the subtitles")
    func everyVariantCarriesThem() {
        let variants = Self.lines().filter { $0.hasPrefix("#EXT-X-STREAM-INF") }

        #expect(variants.count == 2)
        #expect(variants.allSatisfy { $0.hasSuffix("SUBTITLES=\"subtitles\"") })
    }

    @Test("FR-PLAY-01: what NPO's manifest names relative to itself is named in full, and a key is left alone")
    func addressesAreMadeAbsolute() {
        let lines = Self.lines()

        #expect(lines.contains(URL(filePath: "/signed/prid/video/low.m3u8").absoluteString))
        #expect(lines.contains(URL(filePath: "/signed/prid/video/high.m3u8").absoluteString))
        let sound = URL(filePath: "/signed/prid/audio/sound.m3u8").absoluteString
        #expect(lines.contains { $0.contains("URI=\"\(sound)\"") })
        #expect(lines.contains { $0.contains("URI=\"skd://key-1\"") })
    }

    @Test("FR-PLAY-01: the playlist of a track is the one file, for as long as the programme lasts")
    func playlistIsOneSegment() {
        let lines = SubtitledManifest.playlist(for: Self.dutch, lasting: .milliseconds(2_538_540))
            .split(separator: "\n")
            .map(String.init)

        #expect(lines.first == "#EXTM3U")
        #expect(lines.contains("#EXTINF:2538.540,"))
        #expect(lines.contains("#EXT-X-TARGETDURATION:2539"))
        #expect(lines.contains(Self.dutch.location.absoluteString))
        #expect(lines.last == "#EXT-X-ENDLIST")
    }

    @Test("FR-PLAY-01: the address of a track's playlist is told apart from the manifest's")
    func playlistAddressesRoundTrip() throws {
        let address = try #require(SubtitledManifest.playlistAddress(for: 1))

        #expect(SubtitledManifest.trackIndex(of: address) == 1)
        #expect(try SubtitledManifest.trackIndex(of: #require(SubtitledManifest.manifest)) == nil)
        #expect(address.pathExtension == "m3u8")
    }

    @Test("FR-PLAY-01: a name with a quote in it cannot end its attribute early")
    func quotesAreDropped() throws {
        let odd = SubtitleTrack(language: "nl", name: "Neder\"lands", location: Self.dutch.location)

        let rendition = try #require(Self.lines(adding: [odd]).first { $0.contains("TYPE=SUBTITLES") })

        #expect(rendition.contains("NAME=\"Nederlands\""))
    }

    // MARK: The loader

    private static func stream(subtitles: [SubtitleTrack] = [dutch],
                               duration: Duration? = .seconds(600)) -> PlayableStream {
        PlayableStream(manifest: base, protection: nil, subtitles: subtitles, duration: duration)
    }

    @Test("FR-PLAY-01: the player is given NPO's own manifest, fetched now, with the subtitles added")
    func loaderAnswersWithTheManifest() async throws {
        let transport = StubTransport { _ in HTTPResponse(status: 200, body: Data(Self.original.utf8)) }
        let loader = try #require(ManifestLoader(stream: Self.stream(), transport: transport))

        let manifest = try await loader.answer(for: #require(SubtitledManifest.manifest))
        let playlist = try await loader.answer(for: #require(SubtitledManifest.playlistAddress(for: 0)))

        #expect(manifest.contains("TYPE=SUBTITLES"))
        #expect(playlist.contains(Self.dutch.location.absoluteString))
        // The playlist is made here; only the manifest is asked of NPO.
        #expect(transport.sent.map(\.url) == [Self.base])
    }

    @Test("FR-PLAY-10: a manifest NPO will not give is an error the player can retry")
    func refusedManifestIsAnError() async throws {
        let transport = StubTransport { _ in HTTPResponse(status: 403) }
        let loader = try #require(ManifestLoader(stream: Self.stream(), transport: transport))

        await #expect(throws: BackendError.unexpectedResponse(status: 403)) {
            _ = try await loader.answer(for: #require(SubtitledManifest.manifest))
        }
    }

    @Test("FR-PLAY-01: a stream with no subtitles, or of unknown length, is played from NPO's manifest as it is")
    func nothingToAddMeansNoLoader() {
        let transport = StubTransport { _ in HTTPResponse(status: 200) }

        #expect(ManifestLoader(stream: Self.stream(subtitles: []), transport: transport) == nil)
        #expect(ManifestLoader(stream: Self.stream(duration: nil), transport: transport) == nil)
    }

    // MARK: What NPO says

    private static func answer(subtitles: String) -> Data {
        Data("""
        {"stream": {"streamURL": "https://cdn.example/stream.m3u8", "drm": null},
         "assets": {"subtitles": \(subtitles)},
         "metadata": {"duration": 2538540}}
        """.utf8)
    }

    @Test("FR-PLAY-01: the subtitles and the length NPO sends with a stream are read")
    func subtitlesAreRead() throws {
        let json = Self.answer(subtitles: """
        [{"iso": "nl", "name": "Nederlands", "aiGenerated": false, "location": "https://cdn.example/nl/a.vtt"}]
        """)

        let stream = try #require(try JSONDecoder().decode(StreamLinkBody.self, from: json).playableStream)

        #expect(stream.subtitles.map(\.language) == ["nl"])
        #expect(stream.subtitles.map(\.name) == ["Nederlands"])
        #expect(stream.duration == .milliseconds(2_538_540))
    }

    @Test("FR-PLAY-01: a stream without subtitles, or with one that cannot be used, still plays",
          arguments: ["null", "[]", #"[{"iso": "nl"}]"#, #"[{"iso": "nl", "location": "http://cdn.example/a.vtt"}]"#])
    func unusableSubtitlesAreLeftOut(subtitles: String) throws {
        let body = try JSONDecoder().decode(StreamLinkBody.self, from: Self.answer(subtitles: subtitles))

        let stream = try #require(body.playableStream)

        #expect(stream.subtitles.isEmpty)
    }
}
