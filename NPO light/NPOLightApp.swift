//
//  NPOLightApp.swift
//  NPO light
//

import SwiftUI

/// The composition root (ADR 0011): the one place that names a concrete type
/// and hands it down, so that the seams ADR 0009 relies on stay reachable.
///
/// The search history, the pins, the positions, what was watched and what
/// was saved for later are the stores. Where each keeps its data is ADR 0015.
@main
struct NPOLightApp: App {
    /// How long a request to NPO may stay unanswered before it fails, so that
    /// no screen waits for ever on a backend that went quiet.
    private static let requestTimeout: TimeInterval = 15

    /// The most the images kept on disk may take. tvOS may empty it sooner.
    private static let artworkDiskCeiling = 128 * 1024 * 1024

    @State private var appModel: AppModel
    @State private var signInModel: SignInModel
    @State private var modes: ModeModel
    @State private var settings: SettingsModel

    private let backend: Backend
    private let positions: PlaybackCoordinator

    init() {
        let backend = Self.makeBackend()
        self.backend = backend
        positions = PlaybackCoordinator(watched: backend.watchedState,
                                        order: EpisodeOrder(catalogue: backend.catalogue),
                                        clock: SystemClock())
        let appModel = AppModel(authenticator: backend.authenticator)
        _appModel = State(initialValue: appModel)
        _signInModel = State(initialValue: SignInModel(authenticator: backend.authenticator,
                                                       clock: SystemClock(),
                                                       onSignedIn: { appModel.admit($0) }))
        _modes = State(initialValue: backend.modes)
        _settings = State(initialValue: backend.settings { appModel.signOut() })
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel,
                     signInModel: signInModel,
                     modes: modes,
                     settings: settings,
                     homeModel: { [backend] mode in
                         HomeModel(pins: backend.pins,
                                   watched: backend.watchedState,
                                   catalogue: backend.catalogue,
                                   clock: SystemClock(),
                                   mode: mode)
                     },
                     searchModel: { [backend] mode in
                         SearchModel(catalogue: backend.catalogue,
                                     history: backend.searchHistory,
                                     clock: SystemClock(),
                                     mode: mode)
                     },
                     seriesModel: { [backend] series, mode in
                         SeriesDetailModel(summary: series,
                                           catalogue: backend.catalogue,
                                           pins: backend.pins,
                                           watched: backend.watchedState,
                                           mode: mode)
                     },
                     programmeModel: { [backend] programme, mode in
                         ProgrammeDetailModel(summary: programme,
                                              catalogue: backend.catalogue,
                                              watched: backend.watchedState,
                                              mode: mode)
                     },
                     playerModel: { [backend, positions, settings] request, mode in
                         PlayerModel(playable: request.playable,
                                     origin: request.origin,
                                     mode: mode,
                                     starter: backend.playback,
                                     positions: positions,
                                     clock: SystemClock(),
                                     timings: { settings.timings })
                     })
                     .environment(\.artwork, backend.artwork)
        }
    }

    private static func makeBackend() -> Backend {
        #if DEBUG
        // A launch by a test must not reach NPO.
        if let scripted = ScriptedAuthenticator(environment: ProcessInfo.processInfo.environment) {
            let eraser = ScriptedEraser()
            return Backend(authenticator: scripted,
                           catalogue: ScriptedCatalogue(),
                           playback: ScriptedPlayback(),
                           artwork: NoArtwork(),
                           searchHistory: eraser.searches,
                           pins: eraser.pins,
                           progress: eraser.progress,
                           watched: eraser.history,
                           later: eraser.later,
                           eraser: eraser,
                           keepsSettings: false)
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
        let npoPlayback = NPOPlayback(streams: streams,
                                      licenser: FairPlayLicenser(transport: transport),
                                      clock: clock)
        let playback = simulatorPlayback ?? npoPlayback
        let progress = ProgressStore.open(in: .cachesDirectory)
        // Every failure behind the boundary is written down on its way out
        // (ADR 0016).
        return Backend(
            authenticator: LoggedAuthenticator(wrapping: authenticator, log: log),
            catalogue: LoggedCatalogue(wrapping: NPOCatalogue(authenticator: authenticator, profiles: profiles),
                                       log: log),
            playback: LoggedPlayback(wrapping: playback, log: log),
            artwork: ArtworkLoader(transport: URLSessionTransport(session: artworkSession()), log: log),
            searchHistory: SearchHistoryStore(),
            pins: PinStore(),
            progress: progress,
            watched: WatchHistoryStore(),
            later: WatchLaterStore(),
            eraser: LocalDataEraser(progress: progress)
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

    /// What plays instead of NPO's streams where they cannot: a debug build
    /// on the simulator plays the test card, with the real catalogue and the
    /// real stores around it (ADR 0019). `nil` everywhere else.
    private static var simulatorPlayback: (any PlaybackStarting)? {
        #if DEBUG && targetEnvironment(simulator)
        ScriptedPlayback()
        #else
        nil
        #endif
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
    let pins: any Pins
    let progress: any ProgressKeeping
    let watched: any WatchHistory
    let later: any WatchLater

    let eraser: any LocalDataErasing

    /// The mode and the settings of a launch by a test are gone with the
    /// process; the app's own are kept (FR-MODE-01, FR-SET-02).
    var keepsSettings = true

    @MainActor
    func settings(signOut: @escaping () -> Void) -> SettingsModel {
        guard keepsSettings else {
            return SettingsModel(timings: Timings(), eraser: eraser, keep: { _, _ in }, signOut: signOut)
        }
        let stored = StoredTimings()
        return SettingsModel(timings: stored.timings,
                             eraser: eraser,
                             keep: { stored.keep($0, for: $1) },
                             signOut: signOut)
    }

    @MainActor var modes: ModeModel {
        guard keepsSettings else {
            return ModeModel(initial: .normal, catalogue: catalogue, keep: { _ in })
        }
        let stored = StoredMode()
        return ModeModel(initial: stored.mode, catalogue: catalogue, keep: { stored.mode = $0 })
    }

    /// What a page that shows watched state reads.
    var watchedState: WatchedState {
        WatchedState(progress: progress, history: watched, later: later)
    }
}
