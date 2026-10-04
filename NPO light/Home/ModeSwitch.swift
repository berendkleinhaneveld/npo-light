//
//  ModeSwitch.swift
//  NPO light
//

import SwiftUI

/// The way to the other mode: one action, always on the home page, with
/// nothing asked (FR-MODE-02). An account without an NPO kids profile gets
/// the reason there is no kids mode instead.
struct ModeSwitch: View {
    let modes: ModeModel

    var body: some View {
        if modes.canSwitch {
            switch modes.current {
            case .normal:
                Button("Naar kindermodus", systemImage: "star") { modes.switchMode() }
                    .accessibilityIdentifier("mode-to-kids")
            case .kids:
                Button("Naar gewone modus", systemImage: "person") { modes.switchMode() }
                    .accessibilityIdentifier("mode-to-normal")
            }
        } else if modes.explainsMissingProfile {
            Text("Voor de kindermodus is een kinderprofiel nodig. Maak er een in de app van NPO of op npo.nl.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 520, alignment: .trailing)
                .accessibilityIdentifier("mode-kids-missing")
        }
    }
}

/// Says that this is kids mode, on every page: a symbol and the word, not a
/// colour alone (FR-MODE-03, NFR-A11Y-04).
struct KidsModeBadge: View {
    var body: some View {
        Label("Kindermodus", systemImage: "star.fill")
            .font(.caption.bold())
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.yellow, in: Capsule())
            .foregroundStyle(.black)
            .accessibilityIdentifier("kids-mode-badge")
    }
}

#if DEBUG
#Preview("To kids mode") {
    ModeSwitch(modes: .scripted())
}

#Preview("Kids mode") {
    VStack(spacing: 40) {
        ModeSwitch(modes: .scripted(.kids))
        KidsModeBadge()
    }
}
#endif
