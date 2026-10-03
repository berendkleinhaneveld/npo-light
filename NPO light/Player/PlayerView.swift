//
//  PlayerView.swift
//  NPO light
//

import AVKit
import SwiftUI

/// The system player, and nothing drawn over its controls (FR-PLAY-01).
struct PlayerView: View {
    let model: PlayerModel

    var body: some View {
        content
            .task { await model.start() }
            .onDisappear { model.stop() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .preparing:
            ProgressView()
        case .playing(let playback):
            VideoPlayer(player: playback.player)
                .ignoresSafeArea()
        case .failed(let problem):
            PlayerProblemView(title: model.playable.title, problem: problem) {
                Task { await model.start() }
            }
        }
    }
}

/// Why nothing is playing, and a way forward. The Menu button leaves, as
/// everywhere.
struct PlayerProblemView: View {
    let title: String
    let problem: PlayerModel.Problem
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text(verbatim: title)
                .font(.title3.bold())
            Text(explanation)
                .font(.headline)
                .multilineTextAlignment(.center)
            // An item that is gone will not come back by asking again.
            if problem != .unavailable {
                Button("Opnieuw proberen", action: retry)
            }
        }
        .frame(maxWidth: 1200)
        .padding(80)
    }

    private var explanation: LocalizedStringKey {
        switch problem {
        case .unavailable:
            "Dit is niet meer beschikbaar bij NPO."
        case .unreachable:
            "Deze tv kan NPO nu niet bereiken. Controleer het netwerk en probeer het opnieuw."
        case .failed:
            "Afspelen is niet gelukt. Probeer het opnieuw."
        }
    }
}

#if DEBUG
#Preview("Player") {
    PlayerView(model: PlayerModel(playable: ScriptedCatalogue.results.playables[0],
                                  mode: .normal,
                                  starter: ScriptedPlayback()))
}

#Preview("Unavailable") {
    PlayerProblemView(title: "Freeks wilde wereld", problem: .unavailable, retry: {})
}

#Preview("Failed") {
    PlayerProblemView(title: "Freeks wilde wereld", problem: .failed, retry: {})
}
#endif
