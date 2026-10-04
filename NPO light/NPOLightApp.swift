//
//  NPOLightApp.swift
//  NPO light
//

import SwiftUI

/// The composition root (ADR 0011): the one place that names a concrete type
/// and hands it down, so that the seams ADR 0009 relies on stay reachable.
///
/// The stores and the model container are not here yet. Whether an Apple TV
/// has anywhere to put that container is Q-09.
@main
struct NPOLightApp: App {
    /// How long a request to NPO may stay unanswered before it fails, so that
    /// no screen waits for ever on a backend that went quiet.
    private static let requestTimeout: TimeInterval = 15

    @State private var appModel: AppModel
    @State private var signInModel: SignInModel
    @State private var homeModel = HomeModel()
    @State private var searchModel: SearchModel

    private let catalogue: any Catalogue

    init() {
        let backend = Self.makeBackend()
        catalogue = backend.catalogue
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
                     seriesModel: { [catalogue] in
                         SeriesDetailModel(summary: $0, catalogue: catalogue, mode: .normal)
                     })
        }
    }

    private static func makeBackend() -> (authenticator: any Authenticating, catalogue: any Catalogue) {
        #if DEBUG
        // A launch by a test must not reach NPO.
        if let scripted = ScriptedAuthenticator(environment: ProcessInfo.processInfo.environment) {
            return (scripted, ScriptedCatalogue())
        }
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        let authenticator = NPOAuthenticator(
            transport: URLSessionTransport(session: URLSession(configuration: configuration)),
            tokenStore: KeychainTokenStore(),
            clock: SystemClock()
        )
        return (authenticator, NPOCatalogue(authenticator: authenticator))
    }
}
