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
struct SeriesDetailView: View {
    /// How much of the first screen the image takes. The rest shows the top
    /// of the seasons, which says there is something below.
    static let heroHeight: CGFloat = 620

    nonisolated private enum Part: Hashable, Sendable {
        case hero
        case seasons
    }

    let model: SeriesDetailModel
    let play: (PlayRequest) -> Void

    @State private var scroll = ScrollPosition(idType: Part.self)
    @State private var isBrowsing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SeriesHero(title: model.summary.title,
                           detail: loadedDetail,
                           fallbackArtwork: model.summary.artwork,
                           primary: model.primary,
                           isFullyWatched: model.isFullyWatched,
                           isPinned: model.isPinned,
                           play: playPrimary,
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

    private func playPrimary() {
        guard let primary = model.primary else { return }
        play(model.request(for: primary.episode, in: primary.season))
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
            SeasonEpisodesView(model: model,
                               play: { play(model.request(for: $0)) },
                               focusEntered: { isBrowsing = true })
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

#if DEBUG
#Preview("Series") {
    SeriesDetailView(model: .scripted(ScriptedCatalogue.results.series[0]), play: { _ in })
}

#Preview("Picker") {
    SeasonPicker(seasons: ScriptedCatalogue.seasons, shown: ScriptedCatalogue.seasons[1].id) { season, _ in season }
}
#endif
