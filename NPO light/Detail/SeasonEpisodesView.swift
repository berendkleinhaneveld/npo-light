//
//  SeasonEpisodesView.swift
//  NPO light
//

import SwiftUI

/// A season's episodes, one line each, with the focused one previewed.
struct SeasonEpisodesView: View {
    let model: SeriesDetailModel
    let play: (Playable) -> Void

    /// Focus came to an episode.
    var focusEntered: () -> Void = {}

    @FocusState private var focused: EpisodeID?

    var body: some View {
        switch model.episodes {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .failed:
            VStack(alignment: .leading, spacing: 24) {
                Text("De afleveringen konden niet worden opgehaald.")
                Button("Opnieuw proberen") { model.retryEpisodes() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        case .loaded(let episodes):
            HStack(alignment: .top, spacing: 60) {
                list(episodes)
                if let previewed = model.previewed {
                    VStack(alignment: .leading, spacing: 32) {
                        EpisodePreview(episode: previewed, watched: model.watched(previewed.id))
                        // The long press is not the only way to learn it
                        // exists (NFR-A11Y-01).
                        Text("Houd de selectieknop ingedrukt op een aflevering om hem voor later te bewaren.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 560, alignment: .leading)
                    }
                }
            }
            // The whole width takes focus: a season far along the picker is
            // not above the list, and down from it has to arrive here all
            // the same (NFR-A11Y-01).
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
    }

    private func list(_ episodes: [Playable]) -> some View {
        ScrollView {
            // Not a lazy stack: in one, the last episode of a season was
            // drawn and could not take focus. A season is a few hundred
            // one-line rows at most.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(episodes) { episode in
                    Button { play(episode) } label: {
                        HStack {
                            HStack(spacing: 16) {
                                WatchedMark(watched: model.watched(episode.id))
                                Text(verbatim: episode.title)
                                    .lineLimit(1)
                            }
                            Spacer()
                            // In words and a symbol, not by dimming alone
                            // (NFR-A11Y-04).
                            if model.unavailable.contains(episode.id) {
                                Label("Niet meer beschikbaar", systemImage: "nosign")
                                    .foregroundStyle(.secondary)
                            } else if let caption = episode.caption {
                                Text(verbatim: caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .focused($focused, equals: episode.id)
                    .contextMenu {
                        // The label says which of the two it does
                        // (FR-LATER-03).
                        if model.saved.contains(episode.id) {
                            Button("Verwijderen uit Later kijken", systemImage: "bookmark.slash") {
                                Task { await model.toggleSave(episode) }
                            }
                        } else {
                            Button("Later kijken", systemImage: "bookmark") {
                                Task { await model.toggleSave(episode) }
                            }
                        }
                    }
                    // The description is read out with the episode, since the
                    // preview beside the list is not where VoiceOver is.
                    .accessibilityValue(Text(verbatim: episode.synopsis ?? ""))
                    .accessibilityHint(WatchedMark.words(for: model.watched(episode.id)))
                    .accessibilityIdentifier("episode-\(episode.id.rawValue)")
                }
            }
            .padding(.vertical, 16)
        }
        .frame(width: 900)
        .focusSection()
        .onChange(of: focused) { _, episode in
            guard let episode else { return }
            focusEntered()
            model.focus(episode)
        }
    }
}

/// Whether an episode was watched, as a symbol with a shape of its own for
/// each state: not a colour alone (NFR-A11Y-04).
struct WatchedMark: View {
    let watched: SeriesDetailModel.Watched

    var body: some View {
        Image(systemName: symbol)
            .opacity(watched == .notStarted ? 0.35 : 1)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch watched {
        case .notStarted: "circle"
        case .started: "circle.lefthalf.filled"
        case .finished: "checkmark.circle.fill"
        }
    }

    /// The state in words, for the preview and for VoiceOver.
    static func words(for watched: SeriesDetailModel.Watched) -> Text {
        switch watched {
        case .notStarted: Text("Niet gezien")
        case .started: Text("Half gezien")
        case .finished: Text("Gezien")
        }
    }
}

/// The focused episode's image, title, watched state and description.
struct EpisodePreview: View {
    let episode: Playable
    var watched = SeriesDetailModel.Watched.notStarted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Small enough to leave the description room under it: at
            // 560 wide the image took the height and the text got one line.
            ArtworkView(url: episode.artwork, size: .large)
                .frame(width: 448, height: 252)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(verbatim: episode.title)
                .font(.headline)
            if let caption = episode.caption {
                Text(verbatim: caption)
                    .foregroundStyle(.secondary)
            }
            if watched != .notStarted {
                HStack(spacing: 12) {
                    WatchedMark(watched: watched)
                    WatchedMark.words(for: watched)
                }
                .font(.callout)
                .accessibilityIdentifier("episode-preview-watched")
            }
            // A missing description leaves no empty box.
            if let synopsis = episode.synopsis {
                Text(verbatim: synopsis)
                    .font(.callout)
                    .lineLimit(6)
            }
        }
        .frame(width: 560, alignment: .leading)
        .accessibilityIdentifier("episode-preview")
    }
}

#if DEBUG
#Preview("Episodes") {
    SeasonEpisodesView(model: .scripted(ScriptedCatalogue.results.series[0]), play: { _ in })
}

#Preview("Preview") {
    EpisodePreview(episode: ScriptedCatalogue.results.episodes[0], watched: .finished)
}
#endif
