//
//  NPOLightApp.swift
//  NPO light
//

import SwiftUI

/// The composition root (ADR 0010): the one place that names a concrete type
/// and hands it down, so that the seams ADR 0009 relies on stay reachable.
///
/// There is nothing to compose yet. The NPO client, the stores and the model
/// container arrive with the features that need them — and whether an Apple TV
/// has anywhere to put that container is Q-09, which is why the crash-on-launch
/// the Xcode template shipped here is gone rather than reworked.
@main
struct NPOLightApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
