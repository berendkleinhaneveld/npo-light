//
//  ScriptedAuthenticator.swift
//  NPO light
//

#if DEBUG
import Foundation

/// An `Authenticating` that never leaves the process, for previews and for the
/// app when a test launches it (ADR 0009).
///
/// A UI test drives a separate process and cannot inject a protocol into it, so
/// it names a scenario in the launch environment instead. Debug builds only:
/// none of this is in the app that ships.
nonisolated struct ScriptedAuthenticator: Authenticating {
    enum Scenario: String {
        /// Nothing stored; the code stays on screen, never approved.
        case awaitingApproval = "awaiting-approval"

        /// A stored session with NPO Plus.
        case signedIn = "signed-in"
    }

    /// The environment variable a UI test sets to pick a scenario.
    static let environmentKey = "NPO_LIGHT_SCENARIO"

    static let account = Account(identifier: "scripted-account", hasPlus: true)

    /// The code from the captured response, at NPO's own pairing address.
    static var challenge: DeviceCodeChallenge {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "id.npo.nl"
        components.path = "/koppel"
        let short = components.url ?? URL(filePath: "/koppel")
        components.queryItems = [URLQueryItem(name: "userCode", value: "51411921")]
        return DeviceCodeChallenge(
            userCode: "51411921",
            verificationURL: short,
            completeVerificationURL: components.url ?? short,
            pollInterval: .seconds(5),
            expiresAt: .distantFuture,
            deviceCode: "scripted-device-code"
        )
    }

    private let scenario: Scenario

    init(_ scenario: Scenario) {
        self.scenario = scenario
    }

    /// The scenario this launch asks for, if it asks for one. A unit-test host
    /// that names none still gets one: the app under test must not start a real
    /// sign-in at NPO just because the suite launched it.
    init?(environment: [String: String]) {
        if let scenario = environment[Self.environmentKey].flatMap(Scenario.init(rawValue:)) {
            self.init(scenario)
        } else if environment["XCTestConfigurationFilePath"] != nil {
            self.init(.awaitingApproval)
        } else {
            return nil
        }
    }

    func startSignIn() async throws -> DeviceCodeChallenge {
        Self.challenge
    }

    func awaitApproval(of challenge: DeviceCodeChallenge) async throws -> Account {
        while true {
            try await Task.sleep(for: .seconds(3600))
        }
    }

    func restoredAccount() async throws -> Account? {
        scenario == .signedIn ? Self.account : nil
    }

    func signOut() throws {}
}
#endif
