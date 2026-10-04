//
//  SeriesDetailView.swift
//  NPO light
//

import SwiftUI

/// A series: its header, a season picker, and one season's episodes with the
/// focused one previewed beside them (FR-CONTENT-03, -07, -08).
///
/// Watched state is not here yet: it needs the store of positions.
struct SeriesDetailView: View {
    let model: SeriesDetailModel
    let play: (Playable) -> Void

    @Namespace private var page

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SeriesHeaderView(title: model.summary.title,
                             detail: loadedDetail,
                             fallbackArtwork: model.summary.artwork,
                             isPinned: model.isPinned) {
                Task { await model.togglePin() }
            }
            // The page opens on its seasons and episodes, as it did before
            // there was a button above them.
            content
                .prefersDefaultFocus(in: page)
        }
        .focusScope(page)
        .padding(.horizontal, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await model.load() }
    }

    private var loadedDetail: SeriesDetail? {
        if case .loaded(let detail) = model.page { return detail }
        return nil
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .loaded:
            SeasonPicker(seasons: model.pickerSeasons, shown: model.shownSeason) { model.show($0) }
            SeasonEpisodesView(model: model, play: play)
        case .unavailable:
            Text("Deze serie is niet meer beschikbaar.")
                .font(.headline)
        case .failed:
            VStack(alignment: .leading, spacing: 24) {
                Text("Deze tv kan NPO nu niet bereiken. Controleer het netwerk en probeer het opnieuw.")
                Button("Opnieuw proberen") {
                    Task { await model.load() }
                }
            }
        }
    }
}

/// The series' own image, title and description, and its pin (FR-HOME-03).
struct SeriesHeaderView: View {
    let title: String
    let detail: SeriesDetail?
    let fallbackArtwork: URL?
    let isPinned: Bool
    let togglePin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            ArtworkView(url: detail?.artwork ?? fallbackArtwork, size: .large)
                .frame(width: 480, height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: detail?.title ?? title)
                    .font(.title2)
                if let synopsis = detail?.synopsis {
                    Text(verbatim: synopsis)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
                pin
            }
        }
        .focusSection()
    }

    /// The words say which of the two it does, not only the symbol
    /// (NFR-A11Y-04).
    @ViewBuilder private var pin: some View {
        if isPinned {
            Button("Losmaken", systemImage: "pin.slash", action: togglePin)
                .accessibilityIdentifier("series-unpin")
        } else {
            Button("Vastzetten", systemImage: "pin", action: togglePin)
                .accessibilityIdentifier("series-pin")
        }
    }
}

/// One entry per season, in NPO's order. Moving focus along it changes the
/// season shown, and coming back up lands on the season being shown.
struct SeasonPicker: View {
    let seasons: [Season]
    let shown: SeasonID?
    let show: (SeasonID) -> Void

    @FocusState private var focused: SeasonID?

    var body: some View {
        if !seasons.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(seasons) { season in
                        Button { show(season.id) } label: {
                            // The mark, not only a colour, says which season
                            // is shown (NFR-A11Y-04).
                            Label {
                                Text(verbatim: season.title)
                            } icon: {
                                Image(systemName: "checkmark")
                                    .opacity(season.id == shown ? 1 : 0)
                            }
                        }
                        .focused($focused, equals: season.id)
                        .accessibilityAddTraits(season.id == shown ? .isSelected : [])
                        .accessibilityIdentifier("season-\(season.id.rawValue)")
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            .focusSection()
            .defaultFocus($focused, shown)
            .onChange(of: focused) { _, season in
                if let season { show(season) }
            }
        }
    }
}

/// A season's episodes, one line each, with the focused one previewed.
struct SeasonEpisodesView: View {
    let model: SeriesDetailModel
    let play: (Playable) -> Void

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
        case .loaded(let episodes):
            HStack(alignment: .top, spacing: 60) {
                list(episodes)
                if let previewed = model.previewed {
                    EpisodePreview(episode: previewed)
                }
            }
        }
    }

    private func list(_ episodes: [Playable]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(episodes) { episode in
                    Button { play(episode) } label: {
                        HStack {
                            Text(verbatim: episode.title)
                                .lineLimit(1)
                            Spacer()
                            if let caption = episode.caption {
                                Text(verbatim: caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .focused($focused, equals: episode.id)
                    // The description is read out with the episode, since the
                    // preview beside the list is not where VoiceOver is.
                    .accessibilityValue(Text(verbatim: episode.synopsis ?? ""))
                    .accessibilityIdentifier("episode-\(episode.id.rawValue)")
                }
            }
            .padding(.vertical, 16)
        }
        .frame(width: 900)
        .focusSection()
        .onChange(of: focused) { _, episode in
            if let episode { model.focus(episode) }
        }
    }
}

/// The focused episode's image, title and description.
struct EpisodePreview: View {
    let episode: Playable

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ArtworkView(url: episode.artwork, size: .large)
                .frame(width: 560, height: 315)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(verbatim: episode.title)
                .font(.headline)
            if let caption = episode.caption {
                Text(verbatim: caption)
                    .foregroundStyle(.secondary)
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
#Preview("Series") {
    SeriesDetailView(model: .scripted(ScriptedCatalogue.results.series[0]), play: { _ in })
}

#Preview("Header") {
    SeriesHeaderView(title: "Freeks wilde wereld", detail: nil, fallbackArtwork: nil, isPinned: false) {}
}

#Preview("Picker") {
    SeasonPicker(seasons: ScriptedCatalogue.seasons, shown: ScriptedCatalogue.seasons[1].id, show: { _ in })
}

#Preview("Preview") {
    EpisodePreview(episode: ScriptedCatalogue.results.episodes[0])
}
#endif
