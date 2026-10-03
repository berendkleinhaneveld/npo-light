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

    init() {
        let authenticator = Self.makeAuthenticator()
        let appModel = AppModel(authenticator: authenticator)
        _appModel = State(initialValue: appModel)
        _signInModel = State(initialValue: SignInModel(authenticator: authenticator,
                                                       clock: SystemClock(),
                                                       onSignedIn: { appModel.admit($0) }))
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, signInModel: signInModel)
        }
    }

    private static func makeAuthenticator() -> any Authenticating {
        #if DEBUG
        // A launch by a test must not start a real sign-in at NPO.
        if let scripted = ScriptedAuthenticator(environment: ProcessInfo.processInfo.environment) {
            return scripted
        }
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        return NPOAuthenticator(
            transport: URLSessionTransport(session: URLSession(configuration: configuration)),
            tokenStore: KeychainTokenStore(),
            clock: SystemClock()
        )
    }
}
