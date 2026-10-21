import SwiftUI

/// An eager list preserves focus at the end of a season. Its rows own their
/// focus state so navigation does not rebuild every episode's button.
struct SeasonEpisodeList: View {
    let model: SeriesDetailModel
    let episodes: [Playable]
    let play: (Playable) -> Void
    let focusEntered: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(episodes) { episode in
                    SeasonEpisodeRow(model: model, episode: episode, play: play, focusEntered: focusEntered)
                }
            }
            .padding(.vertical, 16)
        }
        .frame(width: 900)
        .focusSection()
    }
}

private struct SeasonEpisodeRow: View {
    let model: SeriesDetailModel
    let episode: Playable
    let play: (Playable) -> Void
    let focusEntered: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
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
        .focused($isFocused)
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
        .onChange(of: isFocused) { _, isFocused in
            guard isFocused else { return }
            focusEntered()
            model.focus(episode.id)
        }
    }
}

#if DEBUG
#Preview("List") {
    SeasonEpisodeList(model: .scripted(ScriptedCatalogue.results.series[0]),
                      episodes: ScriptedCatalogue.results.episodes,
                      play: { _ in }, focusEntered: {})
}

#Preview("Row") {
    SeasonEpisodeRow(model: .scripted(ScriptedCatalogue.results.series[0]),
                     episode: ScriptedCatalogue.results.episodes[0],
                     play: { _ in }, focusEntered: {})
}
#endif
