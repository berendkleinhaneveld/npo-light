//
//  SeriesDetailView.swift
//  NPO light
//

import SwiftUI

/// A series: its image across the top of the page with the title and the
/// actions on it, and under that the seasons, with one season's episodes and
/// the focused one previewed beside them (FR-CONTENT-03, -07, -08).
///
/// The page is two screens high. It opens on the first, and moves to the
/// second when focus goes into the seasons, so that the list has the whole
/// height of the television.
///
/// Watched state is not here yet: it needs the store of positions.
struct SeriesDetailView: View {
    /// How much of the first screen the image takes. The rest shows the top
    /// of the seasons, which says there is something below.
    static let heroHeight: CGFloat = 620

    nonisolated private enum Part: Hashable, Sendable {
        case hero
        case seasons
    }

    let model: SeriesDetailModel
    let play: (Playable) -> Void

    @State private var scroll = ScrollPosition(idType: Part.self)
    @State private var isBrowsing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SeriesHero(title: model.summary.title,
                           detail: loadedDetail,
                           fallbackArtwork: model.summary.artwork,
                           isPinned: model.isPinned,
                           togglePin: { Task { await model.togglePin() } },
                           focused: { isBrowsing = false })
                    .id(Part.hero)
                seasons
                    .id(Part.seasons)
            }
            .scrollTargetLayout()
        }
        .scrollPosition($scroll)
        // The page moves between its two screens and nowhere else. Left to
        // itself the system also scrolls for whatever has focus, which moved
        // the seasons down again when focus went along the picker.
        .scrollDisabled(true)
        .onChange(of: isBrowsing) { _, isBrowsing in
            withAnimation {
                scroll.scrollTo(id: isBrowsing ? Part.seasons : Part.hero, anchor: .top)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .task { await model.load() }
    }

    /// The second screen: exactly as high as the television, inside its safe
    /// area.
    private var seasons: some View {
        VStack(alignment: .leading, spacing: 24) {
            content
        }
        // The lists inside still scroll: only the page is held.
        .scrollDisabled(false)
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .containerRelativeFrame(.vertical, alignment: .top)
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
            SeasonPicker(seasons: model.pickerSeasons, shown: model.shownSeason) {
                isBrowsing = true
                return model.pickerFocusMoved(to: $0, from: $1)
            }
            SeasonEpisodesView(model: model, play: play) { isBrowsing = true }
                // A list of its own for each season. When a season already
                // fetched replaced another in the same list, focus went to
                // rows that were no longer drawn: nothing was highlighted
                // until it was moved back out.
                .id(model.shownSeason)
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
            // The whole width takes focus: the button is not underneath the
            // pin button, and has to be reachable from it (NFR-A11Y-01).
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
    }
}

/// The series' own image from edge to edge, fading into the page, with the
/// title, the description and the pin on it (FR-CONTENT-08, FR-HOME-03).
struct SeriesHero: View {
    let title: String
    let detail: SeriesDetail?
    let fallbackArtwork: URL?
    let isPinned: Bool
    let togglePin: () -> Void

    /// Focus came to one of the actions.
    let focused: () -> Void

    @FocusState private var hasFocus: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // As wide as the screen, and its middle. NPO's images are mostly
            // wide banners, which this suits; a square one shows a band
            // across its middle, and that is the image's doing.
            ArtworkView(url: detail?.artwork ?? fallbackArtwork, size: .full)
            shade
            info
        }
        .frame(maxWidth: .infinity)
        .frame(height: SeriesDetailView.heroHeight)
        .clipped()
        .focusSection()
        .onChange(of: hasFocus) { _, hasFocus in
            if hasFocus { focused() }
        }
    }

    /// Dark where the text is and at the bottom, where the image runs into
    /// the page; the image itself to the right.
    private var shade: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black.opacity(0.85), location: 0.38),
                                   .init(color: .black.opacity(0.15), location: 0.78)],
                           startPoint: .leading,
                           endPoint: .trailing)
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .clear, location: 0.45)],
                           startPoint: .bottom,
                           endPoint: .top)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: detail?.title ?? title)
                .font(.title.bold())
                .lineLimit(2)
            if let synopsis = detail?.synopsis {
                Text(verbatim: synopsis)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            pin
                .padding(.top, 12)
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .padding(.horizontal, 80)
        .padding(.bottom, 40)
    }

    /// The words say which of the two it does, not only the symbol
    /// (NFR-A11Y-04).
    @ViewBuilder private var pin: some View {
        if isPinned {
            Button("Losmaken", systemImage: "pin.slash", action: togglePin)
                .focused($hasFocus)
                .accessibilityIdentifier("series-unpin")
        } else {
            Button("Vastzetten", systemImage: "pin", action: togglePin)
                .focused($hasFocus)
                .accessibilityIdentifier("series-pin")
        }
    }
}

/// One entry per season, in NPO's order. Moving focus along it changes the
/// season shown, and coming into it lands on the season being shown.
struct SeasonPicker: View {
    let seasons: [Season]
    let shown: SeasonID?

    /// Focus reached a season, from another or from outside the picker.
    /// Answers the season that is to have it.
    let focusMoved: (_ season: SeasonID, _ previous: SeasonID?) -> SeasonID

    @FocusState private var focused: SeasonID?

    var body: some View {
        if !seasons.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(seasons) { season in
                        Button { focused = focusMoved(season.id, season.id) } label: {
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
            .onChange(of: focused) { previous, season in
                guard let season else { return }
                let target = focusMoved(season, previous)
                // `defaultFocus` is not asked when focus comes in from a
                // neighbour, so the move to the shown season is made here.
                if target != season { focused = target }
            }
        }
    }
}

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
                    EpisodePreview(episode: previewed)
                }
            }
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
            guard let episode else { return }
            focusEntered()
            model.focus(episode)
        }
    }
}

/// The focused episode's image, title and description.
struct EpisodePreview: View {
    let episode: Playable

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

#Preview("Hero") {
    SeriesHero(title: "Freeks wilde wereld",
               detail: nil,
               fallbackArtwork: nil,
               isPinned: false,
               togglePin: {},
               focused: {})
}

#Preview("Picker") {
    SeasonPicker(seasons: ScriptedCatalogue.seasons, shown: ScriptedCatalogue.seasons[1].id) { season, _ in season }
}

#Preview("Preview") {
    EpisodePreview(episode: ScriptedCatalogue.results.episodes[0])
}
#endif
