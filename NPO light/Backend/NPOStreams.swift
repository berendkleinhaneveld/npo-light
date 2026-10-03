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
    let protection: StreamProtection
}

/// What the FairPlay licence exchange needs. Opaque above the boundary: the
/// app forwards these and computes none of them.
nonisolated struct StreamProtection: Sendable, Equatable {
    let certificateURL: URL
    let licenceURL: URL

    /// The only credential the licence gateway looks at. Never logged.
    let credential: String

    /// When ``credential`` lapses, if NPO said.
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

/// `GET /programs/player/{guid}`: the player token. The programme it names and
/// the next one come with it, and are not read yet.
nonisolated struct PlayerBody: Decodable {
    let token: String
}

/// `POST /stream-link` on the player host.
///
/// The advertisement fields the answer carries are not decoded at all: they
/// are ignored rather than followed (FR-AUTH-05).
nonisolated struct StreamLinkBody: Decodable {
    struct Stream: Decodable {
        let streamURL: String
        let drm: Protection
    }

    struct Protection: Decodable {
        let certificateUrl: String
        let licenseUrl: String
        let expirationInSeconds: Double?
        let httpHeaders: [String: String]?
    }

    static let credentialHeader = "X-Custom-Data"

    let stream: Stream

    var playableStream: PlayableStream? {
        guard let manifest = URL(string: stream.streamURL),
              let certificate = URL(string: stream.drm.certificateUrl),
              let licence = URL(string: stream.drm.licenseUrl),
              let credential = stream.drm.httpHeaders?[Self.credentialHeader] else {
            return nil
        }
        return PlayableStream(
            manifest: manifest,
            protection: StreamProtection(
                certificateURL: certificate,
                licenceURL: licence,
                credential: credential,
                expiresAt: stream.drm.expirationInSeconds.map(Date.init(timeIntervalSince1970:))
            )
        )
    }
}
