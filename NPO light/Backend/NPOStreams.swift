//
//  NPOStreams.swift
//  NPO light
//

import Foundation

/// What is needed to play one item now.
///
/// It is good for about a minute — that is how long NPO's licence credential
/// lives — so it is fetched immediately before playback and never kept
/// (FR-PLAY-11, ADR 0008).
nonisolated struct PlayableStream: Sendable, Equatable {
    /// The signed manifest on NPO's content delivery network.
    let manifest: URL

    /// What the licence exchange needs, or `nil` for a stream that is not
    /// protected: NPO sends some programmes, older ones among them, in the
    /// clear.
    let protection: StreamProtection?

    /// The subtitles NPO has for it. They come beside the stream, not in it
    /// (ADR 0027).
    var subtitles: [SubtitleTrack] = []

    /// How long it lasts, if NPO said.
    var duration: Duration?
}

/// Subtitles in one language, as one file of the whole programme.
nonisolated struct SubtitleTrack: Sendable, Equatable {
    /// The language, as NPO names it: `nl`.
    let language: String

    /// What the system's menu shows: `Nederlands`.
    let name: String

    /// The WebVTT file.
    let location: URL
}

/// What the FairPlay licence exchange needs. Opaque above the boundary: the
/// app forwards these and computes none of them.
nonisolated struct StreamProtection: Sendable, Equatable {
    let certificateURL: URL
    let licenceURL: URL

    /// The credential the licence gateway looks at, when NPO hands one over
    /// to be sent as a header. `nil` when the authorisation is already part of
    /// ``licenceURL``, which is the other shape NPO answers with.
    let credential: String?

    /// When the authorisation lapses, if NPO said.
    let expiresAt: Date?
}

/// The playback chain up to the manifest: a player token from the app backend,
/// exchanged at NPO's player host for a stream.
nonisolated final class NPOStreams: Sendable {
    private let authenticator: NPOAuthenticator
    private let profiles: NPOProfiles
    private let transport: any HTTPTransport

    init(authenticator: NPOAuthenticator, profiles: NPOProfiles, transport: any HTTPTransport) {
        self.authenticator = authenticator
        self.profiles = profiles
        self.transport = transport
    }

    /// Fresh stream details for `episode`. Every call asks NPO again.
    ///
    /// Throws ``BackendError/itemUnavailable`` when NPO no longer has it.
    @concurrent
    func stream(for episode: EpisodeID, in mode: Mode) async throws -> PlayableStream {
        let call = BackendCall(path: NPOWire.playerPath(episode),
                               query: [URLQueryItem(name: "player-environment", value: "production")],
                               profile: try await profiles.profile(for: mode))
        let player = try await authenticator.backendBody(PlayerBody.self, from: call)

        let response = try await transport.reaching(NPOWire.streamLinkRequest(playerToken: player.token))
        guard response.status == 200 else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        guard let body = try? JSONDecoder().decode(StreamLinkBody.self, from: response.body),
              let stream = body.playableStream else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        return stream
    }
}

/// `GET /programs/player/{guid}`: the player token, and the programme it is
/// for. The next programme comes with it, and is not read: which episode
/// follows is taken from the season's list (ADR 0020).
nonisolated struct PlayerBody: Decodable {
    struct Program: Decodable {
        /// The series' name in NPO's addresses. Absent for a programme that
        /// belongs to no series.
        let seriesSlug: String?

        /// The season's identifier, whatever the field is called.
        let seasonSlug: String?
    }

    let token: String
    let program: Program?
}

/// `POST /stream-link` on the player host.
///
/// The advertisement fields the answer carries are not decoded at all: they
/// are ignored rather than followed (FR-AUTH-05).
nonisolated struct StreamLinkBody: Decodable {
    enum StreamKeys: String, CodingKey {
        case streamURL
        case drm
    }

    struct Stream: Decodable {
        let streamURL: String

        /// `null` for a stream that is not protected. NPO always says: an
        /// answer that leaves it out is half an answer, and is not read as
        /// a stream to play in the clear.
        let drm: Protection?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: StreamKeys.self)
            streamURL = try container.decode(String.self, forKey: .streamURL)
            guard container.contains(.drm) else {
                throw DecodingError.keyNotFound(StreamKeys.drm,
                                                .init(codingPath: container.codingPath,
                                                      debugDescription: "A stream says whether it is protected."))
            }
            drm = try container.decodeIfPresent(Protection.self, forKey: .drm)
        }
    }

    struct Protection: Decodable {
        let certificateUrl: String
        let licenseUrl: String
        let expirationInSeconds: Double?
        let httpHeaders: [String: String]?
    }

    struct Assets: Decodable {
        let subtitles: [Subtitle]?
    }

    struct Subtitle: Decodable {
        let iso: String?
        let name: String?
        let location: String?
    }

    struct Metadata: Decodable {
        /// In milliseconds.
        let duration: Double?
    }

    static let credentialHeader = "X-Custom-Data"

    let stream: Stream
    let assets: Assets?
    let metadata: Metadata?

    /// The subtitles that can be used: one that names no language or no
    /// file is left out, and playback goes on without it.
    private var subtitles: [SubtitleTrack] {
        (assets?.subtitles ?? []).compactMap { subtitle in
            guard let language = subtitle.iso, !language.isEmpty,
                  let location = subtitle.location.flatMap(URL.init(string:)), location.scheme == "https" else {
                return nil
            }
            return SubtitleTrack(language: language, name: subtitle.name ?? language, location: location)
        }
    }

    var playableStream: PlayableStream? {
        guard var playable = protectedStream else { return nil }
        playable.subtitles = subtitles
        playable.duration = metadata?.duration.map { .milliseconds(Int($0)) }
        return playable
    }

    private var protectedStream: PlayableStream? {
        guard let manifest = URL(string: stream.streamURL) else { return nil }
        guard let drm = stream.drm else {
            return PlayableStream(manifest: manifest, protection: nil)
        }
        // Protection that cannot be read is not the same as none: playing
        // without it would fail later, and less clearly.
        guard let certificate = URL(string: drm.certificateUrl),
              let licence = URL(string: drm.licenseUrl) else {
            return nil
        }
        return PlayableStream(
            manifest: manifest,
            protection: StreamProtection(
                certificateURL: certificate,
                licenceURL: licence,
                credential: drm.httpHeaders?[Self.credentialHeader],
                expiresAt: drm.expirationInSeconds.map(Date.init(timeIntervalSince1970:))
            )
        )
    }
}
