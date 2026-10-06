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
    /// The most the images kept on disk may take. tvOS may empty it sooner.
    private static let artworkDiskCeiling = 128 * 1024 * 1024

    @State private var appModel: AppModel
    @State private var signInModel: SignInModel
    @State private var modes: ModeModel
    @State private var settings: SettingsModel
    @State private var notice: LaunchNotice

    private let backend: Backend
    private let positions: PlaybackCoordinator

    /// One for both modes: it knows when NPO was last asked, and when a
    /// mode was erased (FR-HOME-12, FR-SET-05).
    private let elsewhere: ContinuedElsewhere

    init() {
        let backend = Self.makeBackend()
        self.backend = backend
        positions = PlaybackCoordinator(watched: backend.watchedState,
                                        order: EpisodeOrder(catalogue: backend.catalogue),
                                        clock: SystemClock())
        let elsewhere = ContinuedElsewhere(catalogue: backend.catalogue,
                                           watched: backend.watchedState,
                                           coordinator: positions,
                                           clock: SystemClock())
        self.elsewhere = elsewhere
        let appModel = backend.appModel
        _appModel = State(initialValue: appModel)
        _signInModel = State(initialValue: SignInModel(authenticator: backend.authenticator,
                                                       clock: SystemClock(),
                                                       onSignedIn: { appModel.admit($0) }))
        _modes = State(initialValue: backend.modes)
        _notice = State(initialValue: LaunchNotice(positionsWereReset: backend.positionsWereReset))
        _settings = State(initialValue: backend.settings(erasingWith: elsewhere) { appModel.signOut() })
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel,
                     signInModel: signInModel,
                     modes: modes,
                     settings: settings,
                     homeModel: { [backend, elsewhere] mode in
                         HomeModel(pins: backend.pins,
                                   watched: backend.watchedState,
                                   catalogue: backend.catalogue,
                                   clock: SystemClock(),
                                   mode: mode,
                                   elsewhere: elsewhere)
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
                                     reports: PlaybackReports(reporter: backend.reports),
                                     timings: { settings.timings })
                     })
                     .environment(\.artwork, backend.artwork)
                     .environment(notice)
        }
    }

    /// Set by a test that wants a launch to say that the store was reset.
    private static let storeResetKey = "NPO_LIGHT_STORE_RESET"

    private static func makeBackend() -> Backend {
        if let scripted = scriptedBackend() { return scripted }
        let clock = SystemClock()
        let log = SystemLog()
        let detail = HTTPLogDetail(environment: ProcessInfo.processInfo.environment, allowsFull: allowsFullHTTPLog)
        let session = URLSession(configuration: RequestPolicy.configuration)
        // Every attempt is logged, so the retries go around the log
        // (NFR-REL-03, ADR 0026).
        let logged = LoggingTransport(wrapping: URLSessionTransport(session: session),
                                      detail: detail,
                                      log: log,
                                      archive: detail == .full ? httpLogArchive(log: log) : nil,
                                      clock: clock)
        let transport = RetryingTransport(wrapping: logged, clock: clock)
        let authenticator = NPOAuthenticator(transport: transport, tokenStore: KeychainTokenStore(), clock: clock)
        let profiles = NPOProfiles(authenticator: authenticator)
        let products = NPOProducts()
        let streams = NPOStreams(authenticator: authenticator,
                                 profiles: profiles,
                                 transport: transport,
                                 products: products)
        let reports = NPOReports(authenticator: authenticator,
                                 profiles: profiles,
                                 products: products,
                                 transport: transport,
                                 clock: clock)
        let npoPlayback = NPOPlayback(streams: streams,
                                      licenser: FairPlayLicenser(transport: transport),
                                      transport: transport,
                                      clock: clock)
        let playback = simulatorPlayback ?? npoPlayback
        let progress = ProgressStore.open(in: .cachesDirectory)
        // Every failure behind the boundary is written down on its way out
        // (ADR 0016).
        let cache = CatalogueCache()
        let catalogue = catalogue(over: LoggedCatalogue(wrapping: NPOCatalogue(authenticator: authenticator,
                                                                               profiles: profiles),
                                                        log: log),
                                  keptIn: cache)
        return Backend(
            authenticator: LoggedAuthenticator(wrapping: authenticator, log: log),
            // The positions NPO's answers come with are taken into the store
            // on their way up (ADR 0028).
            catalogue: PositionTakingCatalogue(wrapping: catalogue,
                                               positions: SharedPositions(progress: progress, clock: clock)),
            playback: LoggedPlayback(wrapping: playback, log: log),
            // What plays in place of NPO's streams is not the programme, and
            // NPO is not told about it (ADR 0019).
            reports: simulatorPlayback == nil ? LoggedReports(wrapping: reports, log: log) : NoReports(),
            // An image that failed in passing is asked for again, like any
            // other request that changes nothing (ADR 0026).
            artwork: ArtworkLoader(transport: RetryingTransport(wrapping: artworkTransport(), clock: clock), log: log),
            searchHistory: SearchHistoryStore(),
            pins: PinStore(),
            progress: progress,
            watched: WatchHistoryStore(),
            later: WatchLaterStore(),
            eraser: LocalDataEraser(progress: progress, catalogue: cache),
            positionsWereReset: progress.wasReset
        )
    }

    /// The stand-ins a launch by a test runs on, which must not reach NPO or
    /// leave anything behind (ADR 0009). `nil` for any other launch, and in
    /// the app that ships.
    private static func scriptedBackend() -> Backend? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let scripted = ScriptedAuthenticator(environment: environment) else { return nil }
        let eraser = environment[ScriptedEraser.filledKey] == nil ? ScriptedEraser() : ScriptedEraser.filled()
        return Backend(authenticator: scripted,
                       catalogue: ScriptedCatalogue(),
                       playback: ScriptedPlayback(),
                       reports: NoReports(),
                       artwork: NoArtwork(),
                       searchHistory: eraser.searches,
                       pins: eraser.pins,
                       progress: eraser.progress,
                       watched: eraser.history,
                       later: eraser.later,
                       eraser: eraser,
                       positionsWereReset: environment[storeResetKey] != nil,
                       keepsSettings: false,
                       admittedBefore: scripted.admittedBefore)
        #else
        nil
        #endif
    }

    /// What NPO answered is kept, so that a page seen before opens without
    /// waiting for it again (ADR 0024). Without a place to keep it, NPO is
    /// simply asked every time.
    private static func catalogue(over npo: any Catalogue, keptIn cache: CatalogueCache?) -> any Catalogue {
        guard let cache else { return npo }
        return CachedCatalogue(wrapping: npo, cache: cache, clock: SystemClock())
    }

    /// Images come over a transport of their own, kept on disk by the
    /// system's cache under a ceiling: NPO lets an image be kept for a year,
    /// and what is on disk need not be fetched again after a relaunch
    /// (ADR 0017). Not through the logging transport, which would keep every
    /// image whole.
    private static func artworkTransport() -> any HTTPTransport {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = RequestPolicy.timeout
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: artworkDiskCeiling)
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSessionTransport(session: URLSession(configuration: configuration))
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
    let reports: any PlaybackReporting
    let artwork: any ArtworkProviding
    let searchHistory: any SearchHistory
    let pins: any Pins
    let progress: any ProgressKeeping
    let watched: any WatchHistory
    let later: any WatchLater

    let eraser: any LocalDataErasing

    /// The store of positions could not be read and was started over
    /// (NFR-REL-05).
    var positionsWereReset = false

    /// The mode and the settings of a launch by a test are gone with the
    /// process; the app's own are kept (FR-MODE-01, FR-SET-02).
    var keepsSettings = true

    /// The account a launch by a test was admitted with before (NFR-REL-01).
    var admittedBefore: Account?

    /// Erasing a mode reaches NPO's row for it too (FR-SET-05).
    @MainActor
    func settings(erasingWith elsewhere: ContinuedElsewhere, signOut: @escaping () -> Void) -> SettingsModel {
        let eraser = ErasingElsewhere(wrapping: eraser, elsewhere: elsewhere)
        guard keepsSettings else {
            return SettingsModel(timings: Timings(), eraser: eraser, keep: { _, _ in }, signOut: signOut)
        }
        let stored = StoredTimings()
        return SettingsModel(timings: stored.timings,
                             eraser: eraser,
                             keep: { stored.keep($0, for: $1) },
                             signOut: signOut)
    }

    @MainActor var appModel: AppModel {
        guard keepsSettings else {
            return AppModel(authenticator: authenticator, clock: SystemClock(), remembered: admittedBefore)
        }
        let stored = StoredAccount()
        return AppModel(authenticator: authenticator,
                        clock: SystemClock(),
                        remembered: stored.account,
                        keep: { stored.account = $0 })
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
