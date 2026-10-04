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
    let homeModel: HomeModel
    let searchModel: SearchModel

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
            HomeView(model: homeModel, search: searchModel)
        case .plusRequired:
            PlusRequiredView { appModel.acknowledgePlusRequired() }
        case .unreachable:
            SignInProblemView(problem: .unreachable) {
                Task { await appModel.restore() }
            }
        }
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
                 homeModel: HomeModel(),
                 searchModel: SearchModel(catalogue: ScriptedCatalogue(), clock: SystemClock(), mode: .normal))
    }
}

#Preview("Signed out") {
    RootPreview(.awaitingApproval)
}

#Preview("Signed in") {
    RootPreview(.signedIn)
}
#endif
