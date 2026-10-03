//
//  SignInView.swift
//  NPO light
//

import SwiftUI

/// A code, an address and a QR code, and a wait (FR-AUTH-06). There is no
/// credential field here and there never will be: the password is typed on the
/// other device, at NPO.
struct SignInView: View {
    let model: SignInModel

    var body: some View {
        VStack(spacing: 48) {
            Text("Log in met je NPO Plus-account")
                .font(.title2)
            content
        }
        .padding(80)
        .task { await model.signIn() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .requesting:
            ProgressView("Code aanvragen…")
        case .waiting(let challenge):
            SignInChallengeView(challenge: challenge)
        case .failed(let problem):
            SignInProblemView(problem: problem) {
                Task { await model.retry() }
            }
        }
    }
}

/// What the user needs to finish on the other device.
struct SignInChallengeView: View {
    let challenge: DeviceCodeChallenge

    var body: some View {
        VStack(spacing: 48) {
            HStack(alignment: .center, spacing: 96) {
                steps
                qrCode
            }
            Label("Wachten op goedkeuring. Deze tv gaat vanzelf verder.", systemImage: "hourglass")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan de QR-code met je telefoon, of ga naar")
                // The short address: the one without the code in it, so that
                // it stays short enough to type.
                Text(verbatim: Self.displayed(challenge.verificationURL))
                    .font(.title3.bold())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Vul deze code in:")
                Text(verbatim: Self.grouped(challenge.userCode))
                    .font(.system(size: 96, weight: .bold, design: .monospaced))
                    .accessibilityLabel(Text(verbatim: challenge.userCode))
                    .speechSpellsOutCharacters()
                    .accessibilityIdentifier("sign-in-code")
            }
            Text("Log in bij NPO en keur de koppeling goed.")
        }
        .font(.headline)
    }

    /// Black on white whatever the interface looks like: a scanner needs the
    /// contrast, and the white padding is the quiet zone it needs around it.
    @ViewBuilder private var qrCode: some View {
        if let image = QRCode.image(encoding: challenge.completeVerificationURL.absoluteString) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 400, height: 400)
                .padding(40)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement()
                .accessibilityLabel("QR-code om in te loggen")
                .accessibilityIdentifier("sign-in-qr-code")
        }
    }

    /// The address as a person would type it: without the scheme.
    static func displayed(_ url: URL) -> String {
        (url.host() ?? "") + url.path()
    }

    /// The code in groups of four, which is how it is read out across a room.
    static func grouped(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4)
            .map { String(code.dropFirst($0).prefix(4)) }
            .joined(separator: " ")
    }
}

/// How a sign-in ended without an account, and the way to try again.
struct SignInProblemView: View {
    let problem: SignInModel.Problem
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text(title)
                .font(.title3.bold())
            Text(explanation)
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(action, action: retry)
        }
        .frame(maxWidth: 1200)
    }

    private var title: LocalizedStringKey {
        switch problem {
        case .expired: "De code is verlopen."
        case .declined: "Inloggen is afgebroken."
        case .unreachable: "Geen verbinding met NPO."
        case .unexpected: "Inloggen is niet gelukt."
        }
    }

    private var explanation: LocalizedStringKey {
        switch problem {
        case .expired:
            "Er is niet op tijd goedgekeurd. Vraag een nieuwe code aan en probeer het nog eens."
        case .declined:
            "Op de telefoon is het koppelen geweigerd of gestopt. Je kunt het opnieuw proberen."
        case .unreachable:
            "Deze tv kan NPO nu niet bereiken. Controleer het netwerk en probeer het opnieuw."
        case .unexpected:
            "NPO gaf een antwoord dat deze app niet begrijpt. Probeer het later opnieuw."
        }
    }

    private var action: LocalizedStringKey {
        switch problem {
        case .expired: "Nieuwe code"
        case .declined: "Opnieuw beginnen"
        case .unreachable, .unexpected: "Opnieuw proberen"
        }
    }
}

#if DEBUG
#Preview("Waiting") {
    SignInView(model: SignInModel(authenticator: ScriptedAuthenticator(.awaitingApproval),
                                  clock: SystemClock(),
                                  onSignedIn: { _ in }))
}

#Preview("Code") {
    SignInChallengeView(challenge: ScriptedAuthenticator.challenge)
}

#Preview("Expired") {
    SignInProblemView(problem: .expired, retry: {})
}

#Preview("Unreachable") {
    SignInProblemView(problem: .unreachable, retry: {})
}
#endif
