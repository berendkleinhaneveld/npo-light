//
//  OnWake.swift
//  NPO light
//

import SwiftUI

/// Runs something when the app is in front again after it was in the
/// background: the television woke, or the app was come back to
/// (FR-CONTENT-09, ADR 0031).
///
/// Only after the background. A scene is also inactive for a moment when
/// the app starts and under the system's own overlays: a page has only just
/// asked then, or nothing can have changed.
private struct OnWake: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasAway = false

    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                wasAway = true
            case .active where wasAway:
                wasAway = false
                Task { await action() }
            default:
                break
            }
        }
    }
}

extension View {
    /// Runs `action` each time the scene becomes active after it was in the
    /// background.
    func onWake(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(OnWake(action: action))
    }
}

#Preview {
    Text(verbatim: "Verder Kijker")
        .onWake {}
}
