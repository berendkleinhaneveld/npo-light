//
//  NPOReports.swift
//  NPO light
//

import Foundation
import Synchronization

/// Reports what plays to NPO, as the events its own player sends
/// (FR-PLAY-12, ADR 0028).
///
/// Only the events about a stream are sent, and of each only what NPO needs
/// to keep a position and what it refuses a report without: no page, no
/// screen, no address of the stream (NFR-PRIV-01).
nonisolated final class NPOReports: PlaybackReporting {
    /// Who a report is about: the same for as long as the sign-in lasts.
    private struct Identity {
        /// The sign-in this was read for. Another account is somebody else.
        let marker: String
        let account: String
        let subject: String?
    }

    private let authenticator: NPOAuthenticator
    private let profiles: NPOProfiles
    private let products: NPOProducts
    private let transport: any HTTPTransport
    private let clock: any Clocking

    /// One run of the app, in the shape NPO's app names its own.
    private let sitting = NPOWire.makeDeviceIdentifier()
    private let hasReported = Mutex(false)
    private let known = Mutex<Identity?>(nil)

    init(authenticator: NPOAuthenticator,
         profiles: NPOProfiles,
         products: NPOProducts,
         transport: any HTTPTransport,
         clock: any Clocking) {
        self.authenticator = authenticator
        self.profiles = profiles
        self.products = products
        self.transport = transport
        self.clock = clock
    }

    @concurrent
    func report(_ event: PlaybackEvent, in mode: Mode) async throws {
        let profile = try await profiles.profile(for: mode)
        let identity = try await identity()
        let product = try await product(for: event.episode, as: profile)
        let device = try authenticator.signInMarker()
        let body = ReportBody(
            event: event,
            product: product,
            account: ReportBody.Account(userId: identity.account,
                                        profileId: profile,
                                        pseudoId: identity.subject,
                                        subscription: NPOWire.plusSubscriptionType),
            device: device,
            sitting: sitting,
            isFirst: hasReported.withLock { reported in
                defer { reported = true }
                return !reported
            },
            at: clock.now
        )
        let request = try NPOWire.reportRequest(body: try JSONEncoder().encode(body), device: device)
        let response = try await transport.reaching(request)
        guard (200..<300).contains(response.status) else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
    }

    /// The account, asked of NPO once for each sign-in.
    private func identity() async throws -> Identity {
        let marker = try authenticator.signInMarker()
        if let known = known.withLock({ $0 }), known.marker == marker { return known }
        let account = try await authenticator.backendBody(AccountBody.self,
                                                          from: BackendCall(path: NPOWire.accountPath))
        let identity = Identity(marker: marker, account: account.guid, subject: try authenticator.subject())
        known.withLock { $0 = identity }
        return identity
    }

    /// NPO's own name for the programme. Playing it told; where something
    /// else played in its place, NPO is asked.
    private func product(for episode: EpisodeID, as profile: String) async throws -> String {
        if let product = products.product(for: episode) { return product }
        let call = BackendCall(path: NPOWire.playerPath(episode),
                               query: [URLQueryItem(name: "player-environment", value: "production")],
                               profile: profile)
        guard let product = try await authenticator.backendBody(PlayerBody.self, from: call).program?.prid else {
            throw BackendError.unexpectedResponse(status: nil)
        }
        products.note(product, for: episode)
        return product
    }
}

/// One event, in the shape NPO's app posts it (Q-13).
nonisolated struct ReportBody: Encodable {
    struct Account: Encodable {
        let userId: String
        let profileId: String
        let pseudoId: String?
        let subscription: String
    }

    struct Platform: Encodable {
        var brand = NPOWire.reportBrand
        var brandId = NPOWire.reportBrandID
        var platformType = NPOWire.reportPlatform
        var platformVersion = NPOWire.reportPlatformVersion
        var environment = NPOWire.reportEnvironment
    }

    struct Stream: Encodable {
        let id: String
        let position: TimeInterval
        let length: TimeInterval
        var isLiveStream = false
        var playerId = NPOWire.reportPlayer
        var playerVersion = NPOWire.reportPlayerVersion
        let seekFrom: TimeInterval?
    }

    struct Parameters: Encodable {
        let npo: Account
        var topspin = Platform()
        let stream: Stream
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventID = "event_id"
        case timestamp = "client_timestamp_iso"
        case device = "party_id"
        case sitting = "session_id"
        case isNewDevice = "is_new_party"
        case isNewSitting = "is_new_session"
        case sdkVersion = "sdk_version"
        case parameters
    }

    let eventType: String
    let eventID: String
    let timestamp: String
    let device: String
    let sitting: String
    var isNewDevice = false
    let isNewSitting: Bool
    var sdkVersion = NPOWire.reportSDKVersion
    let parameters: Parameters

    init(event: PlaybackEvent,
         product: String,
         account: Account,
         device: String,
         sitting: String,
         isFirst: Bool,
         at now: Date) {
        eventType = Self.name(of: event.kind)
        eventID = NPOWire.makeDeviceIdentifier()
        timestamp = now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        self.device = device
        self.sitting = sitting
        isNewSitting = isFirst
        var seekFrom: TimeInterval?
        if case .sought(let from) = event.kind {
            seekFrom = from
        }
        parameters = Parameters(npo: account,
                                stream: Stream(id: product,
                                               position: event.position,
                                               length: event.duration,
                                               seekFrom: seekFrom))
    }

    /// What NPO's player calls each of them.
    static func name(of kind: PlaybackEvent.Kind) -> String {
        switch kind {
        case .loaded: "streamLoadComplete"
        case .started: "streamStart"
        case .waypoint: "streamWaypoint"
        case .paused: "streamPause"
        case .resumed: "streamResume"
        case .sought: "streamSeek"
        case .completed: "streamComplete"
        case .stopped: "streamStop"
        }
    }
}
