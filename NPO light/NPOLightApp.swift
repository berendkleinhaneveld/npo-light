//
//  NPOLightApp.swift
//  NPO light
//

import SwiftUI

/// The composition root (ADR 0011): the one place that names a concrete type
/// and hands it down, so that the seams ADR 0009 relies on stay reachable.
///
/// The search history is the first of the stores. Where each keeps its data
/// is ADR 0015.
@main
struct NPOLightApp: App {
    /// How long a request to NPO may stay unanswered before it fails, so that
    /// no screen waits for ever on a backend that went quiet.
    private static let requestTimeout: TimeInterval = 15

    /// The most the images kept on disk may take. tvOS may empty it sooner.
    private static let artworkDiskCeiling = 128 * 1024 * 1024

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
                                                       history: backend.searchHistory,
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
                     .environment(\.artwork, backend.artwork)
        }
    }

    private static func makeBackend() -> Backend {
        #if DEBUG
        // A launch by a test must not reach NPO.
        if let scripted = ScriptedAuthenticator(environment: ProcessInfo.processInfo.environment) {
            return Backend(authenticator: scripted,
                           catalogue: ScriptedCatalogue(),
                           playback: ScriptedPlayback(),
                           artwork: NoArtwork(),
                           searchHistory: ScriptedSearchHistory())
        }
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        let clock = SystemClock()
        let log = SystemLog()
        let detail = HTTPLogDetail(environment: ProcessInfo.processInfo.environment, allowsFull: allowsFullHTTPLog)
        let session = URLSession(configuration: configuration)
        let transport = LoggingTransport(wrapping: URLSessionTransport(session: session),
                                         detail: detail,
                                         log: log,
                                         archive: detail == .full ? httpLogArchive(log: log) : nil,
                                         clock: clock)
        let authenticator = NPOAuthenticator(transport: transport, tokenStore: KeychainTokenStore(), clock: clock)
        let profiles = NPOProfiles(authenticator: authenticator)
        let streams = NPOStreams(authenticator: authenticator, profiles: profiles, transport: transport)
        let playback = NPOPlayback(streams: streams, licenser: FairPlayLicenser(transport: transport), clock: clock)
        // Every failure behind the boundary is written down on its way out
        // (ADR 0016).
        return Backend(
            authenticator: LoggedAuthenticator(wrapping: authenticator, log: log),
            catalogue: LoggedCatalogue(wrapping: NPOCatalogue(authenticator: authenticator, profiles: profiles),
                                       log: log),
            playback: LoggedPlayback(wrapping: playback, log: log),
            artwork: ArtworkLoader(transport: URLSessionTransport(session: artworkSession()), log: log),
            searchHistory: SearchHistoryStore()
        )
    }

    /// Images come over a session of their own, kept on disk by the system's
    /// cache under a ceiling: NPO lets an image be kept for a year, and what
    /// is on disk need not be fetched again after a relaunch (ADR 0017). Not
    /// through the logging transport, which would keep every image whole.
    private static func artworkSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: artworkDiskCeiling)
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    /// Where requests and responses are kept whole, tidied and announced: the
    /// path is what finds the files on a simulator.
    private static func httpLogArchive(log: any Logging) -> HTTPLogArchive? {
        guard let archive = HTTPLogArchive() else { return nil }
        // Nothing to tidy on a first run, and nothing lost if it fails.
        try? archive.tidy()
        log.record("Keeping requests and responses in \(archive.directory.path())", level: .info, category: .http)
        return archive
    }

    /// Whether a launch may ask for requests and responses whole, credentials
    /// and all. Never in the app that ships (NFR-DIAG-03).
    private static var allowsFullHTTPLog: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// Everything behind the NPO boundary and the local stores, as the rest of
/// the app sees them.
private struct Backend {
    let authenticator: any Authenticating
    let catalogue: any Catalogue
    let playback: any PlaybackStarting
    let artwork: any ArtworkProviding
    let searchHistory: any SearchHistory
}
