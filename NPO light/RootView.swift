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
            // The home page arrives with FR-HOME. Until then a signed-in app
            // shows its name, which is a proper noun and no translation's job.
            Text(verbatim: "NPO light")
                .font(.largeTitle)
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
#Preview("Signed out") {
    let authenticator = ScriptedAuthenticator(.awaitingApproval)
    let appModel = AppModel(authenticator: authenticator)
    RootView(appModel: appModel,
             signInModel: SignInModel(authenticator: authenticator,
                                      clock: SystemClock(),
                                      onSignedIn: { appModel.admit($0) }))
}

#Preview("Signed in") {
    let authenticator = ScriptedAuthenticator(.signedIn)
    let appModel = AppModel(authenticator: authenticator)
    RootView(appModel: appModel,
             signInModel: SignInModel(authenticator: authenticator,
                                      clock: SystemClock(),
                                      onSignedIn: { appModel.admit($0) }))
}
#endif
