//
//  RootView.swift
//  NPO light
//

import SwiftUI

/// The point where the session decides what is on screen (ADR 0011,
/// FR-AUTH-01): without one, sign-in and nothing else.
struct RootView: View {
    let appModel: AppModel
    let signInModel: SignInModel
    let modes: ModeModel
    let settings: SettingsModel

    /// The screens of a mode are made for that mode, and made again when the
    /// mode changes (FR-MODE-05).
    let homeModel: (Mode) -> HomeModel
    let searchModel: (Mode) -> SearchModel
    let seriesModel: (SeriesSummary, Mode) -> SeriesDetailModel
    let programmeModel: (Playable, Mode) -> ProgrammeDetailModel
    let playerModel: (PlayRequest, Mode) -> PlayerModel

    var body: some View {
        content
            .task { await appModel.restore() }
    }

    @ViewBuilder private var content: some View {
        switch appModel.session {
        case .restoring:
            ProgressView()
        case .signedOut:
            SignInView(model: signInModel)
        case .signedIn:
            ModeScreen(modes: modes,
                       settings: settings,
                       homeModel: homeModel,
                       searchModel: searchModel,
                       seriesModel: seriesModel,
                       programmeModel: programmeModel,
                       playerModel: playerModel)
                // Another mode is another home page, from the start: nothing
                // of the mode that was left stays on screen (FR-MODE-02).
                .id(modes.current)
                .task { await modes.load() }
        case .plusRequired:
            PlusRequiredView { appModel.acknowledgePlusRequired() }
        case .unreachable:
            SignInProblemView(problem: .unreachable) {
                Task { await appModel.restore() }
            }
        }
    }
}

/// The home page of one mode, with models of its own for as long as the app
/// is in that mode.
private struct ModeScreen: View {
    let modes: ModeModel
    let settings: SettingsModel
    let seriesModel: (SeriesSummary, Mode) -> SeriesDetailModel
    let programmeModel: (Playable, Mode) -> ProgrammeDetailModel
    let playerModel: (PlayRequest, Mode) -> PlayerModel

    @State private var home: HomeModel
    @State private var search: SearchModel

    init(modes: ModeModel,
         settings: SettingsModel,
         homeModel: (Mode) -> HomeModel,
         searchModel: (Mode) -> SearchModel,
         seriesModel: @escaping (SeriesSummary, Mode) -> SeriesDetailModel,
         programmeModel: @escaping (Playable, Mode) -> ProgrammeDetailModel,
         playerModel: @escaping (PlayRequest, Mode) -> PlayerModel) {
        self.modes = modes
        self.settings = settings
        self.seriesModel = seriesModel
        self.programmeModel = programmeModel
        self.playerModel = playerModel
        _home = State(initialValue: homeModel(modes.current))
        _search = State(initialValue: searchModel(modes.current))
    }

    var body: some View {
        HomeView(model: home,
                 search: search,
                 modes: modes,
                 settings: settings,
                 seriesModel: { seriesModel($0, home.mode) },
                 programmeModel: { programmeModel($0, home.mode) },
                 playerModel: { playerModel($0, home.mode) })
    }
}

#if DEBUG
private struct RootPreview: View {
    let appModel: AppModel
    let signInModel: SignInModel

    init(_ scenario: ScriptedAuthenticator.Scenario) {
        let authenticator = ScriptedAuthenticator(scenario)
        let appModel = AppModel(authenticator: authenticator)
        self.appModel = appModel
        signInModel = SignInModel(authenticator: authenticator,
                                  clock: SystemClock(),
                                  onSignedIn: { appModel.admit($0) })
    }

    var body: some View {
        RootView(appModel: appModel,
                 signInModel: signInModel,
                 modes: .scripted(),
                 settings: .scripted(),
                 homeModel: { .scripted(mode: $0) },
                 searchModel: { .scripted(mode: $0) },
                 seriesModel: { series, _ in .scripted(series) },
                 programmeModel: { programme, _ in .scripted(programme) },
                 playerModel: { request, _ in .scripted(request.playable) })
    }
}

#Preview("Signed out") {
    RootPreview(.awaitingApproval)
}

#Preview("Signed in") {
    RootPreview(.signedIn)
}
#endif
