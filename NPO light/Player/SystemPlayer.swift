//
//  SystemPlayer.swift
//  NPO light
//

import AVKit
import SwiftUI

/// The system's own player (FR-PLAY-01), as a view.
///
/// Not SwiftUI's `VideoPlayer`: that one has no way to put a button on the
/// video that the remote can reach, and the player holds focus while it
/// plays. The system player's contextual action is that way (ADR 0021).
struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    /// A button the player shows over the video for as long as it is given,
    /// and what selecting it does.
    let action: (title: String, run: () -> Void)?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        if let action {
            controller.contextualActions = [UIAction(title: action.title) { _ in action.run() }]
        } else if !controller.contextualActions.isEmpty {
            controller.contextualActions = []
        }
    }
}

/// Says that an episode started by itself, and which (FR-PLAY-05). The way
/// to stop it is the player's own button beside it.
struct NextEpisodeNotice: View {
    let episode: Playable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volgende aflevering speelt")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: [episode.title, episode.caption].compactMap(\.self).joined(separator: " · "))
                .font(.headline)
                .lineLimit(2)
        }
        .padding(32)
        .frame(maxWidth: 800, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("next-episode-notice")
    }
}

#if DEBUG
#Preview("Next episode") {
    NextEpisodeNotice(episode: ScriptedCatalogue.results.episodes[0])
}
#endif
