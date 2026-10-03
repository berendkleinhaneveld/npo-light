//
//  NPOLightApp.swift
//  NPO light
//

import SwiftUI

/// The composition root (ADR 0011): the one place that names a concrete type
/// and hands it down, so that the seams ADR 0009 relies on stay reachable.
///
/// The stores are not here yet. Where they keep their data is ADR 0015.
@main
struct NPOLightApp: App {
    /// How long a request to NPO may stay unanswered before it fails, so that
    /// no screen waits for ever on a backend that went quiet.
    private static let requestTimeout: TimeInterval = 15

    @State private var appModel: AppModel
    @State private var signInModel: SignInModel
    @State private var homeModel = HomeModel()
    @State private var searchModel: SearchModel

    private let backend: Backend

    init() {
        let backend = Self.makeBackend()
        self.backend = backend
        let appModel = AppModel(authenticator: backend.authenticator)
        _appModel = State(initialValue: appModel)
        _signInModel = State(initialValue: SignInModel(authenticator: backend.authenticator,
                                                       clock: SystemClock(),
                                                       onSignedIn: { appModel.admit($0) }))
        // Normal mode until the mode switch exists (FR-MODE-02).
        _searchModel = State(initialValue: SearchModel(catalogue: backend.catalogue,
                                                       clock: SystemClock(),
                                                       mode: .normal))
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel,
                     signInModel: signInModel,
                     homeModel: homeModel,
                     searchModel: searchModel,
                     seriesModel: { [backend] in
                         SeriesDetailModel(summary: $0, catalogue: backend.catalogue, mode: .normal)
                     },
                     playerModel: { [backend] in
                         PlayerModel(playable: $0, mode: .normal, starter: backend.playback)
                     })
        }
    }

    private static func makeBackend() -> Backend {
        #if DEBUG
        // A launch by a test must not reach NPO.
        if let scripted = ScriptedAuthenticator(environment: ProcessInfo.processInfo.environment) {
            return Backend(authenticator: scripted, catalogue: ScriptedCatalogue(), playback: ScriptedPlayback())
        }
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        let transport = URLSessionTransport(session: URLSession(configuration: configuration))
        let clock = SystemClock()
        let authenticator = NPOAuthenticator(transport: transport, tokenStore: KeychainTokenStore(), clock: clock)
        let profiles = NPOProfiles(authenticator: authenticator)
        let streams = NPOStreams(authenticator: authenticator, profiles: profiles, transport: transport)
        return Backend(
            authenticator: authenticator,
            catalogue: NPOCatalogue(authenticator: authenticator, profiles: profiles),
            playback: NPOPlayback(streams: streams, licenser: FairPlayLicenser(transport: transport), clock: clock)
        )
    }
}

/// Everything behind the NPO boundary, as the rest of the app sees it.
private struct Backend {
    let authenticator: any Authenticating
    let catalogue: any Catalogue
    let playback: any PlaybackStarting
}
