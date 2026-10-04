//
//  HomeRow.swift
//  NPO light
//

import SwiftUI

/// One row of the home page: its tiles, or what to do to get one
/// (FR-HOME-02, FR-HOME-06, FR-HOME-09).
///
/// Selecting a tile plays what it continues with. Holding the select button
/// offers the item's page and taking it off the row, so that neither is
/// behind a hidden gesture alone (FR-HOME-05, FR-HOME-08).
struct HomeRow: View {
    enum Kind {
        case pinned
        case continuing
        case later
    }

    let kind: Kind
    let tiles: [HomeTile]
    let select: (HomeTile) -> Void
    let open: (Destination) -> Void
    let remove: (HomeTile) -> Void
    let search: () -> Void

    /// What is on the watch later list, and the way to put a tile's episode
    /// on it or take it off. Only *Kijk verder* offers it (FR-LATER-03).
    var saved: Set<EpisodeID> = []
    var toggleSave: ((HomeTile) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 80)
            if tiles.isEmpty {
                empty
            } else {
                row
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var name: String {
        switch kind {
        case .pinned: "pinned"
        case .continuing: "continue"
        case .later: "later"
        }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .pinned: "Vastgezet"
        case .continuing: "Kijk verder"
        case .later: "Later kijken"
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch kind {
        case .pinned: "Nog niets vastgezet."
        case .continuing: "Nog niets bekeken."
        // Never shown: the row is absent while its list is empty
        // (FR-LATER-05).
        case .later: ""
        }
    }

    private var emptyBody: LocalizedStringKey {
        switch kind {
        case .pinned: "Zoek een serie en zet hem vast. Dan staat hij hier, met de volgende aflevering klaar."
        case .continuing: "Wat je gaat kijken, komt hier te staan. Zoek iets om te beginnen."
        case .later: ""
        }
    }

    private var removal: LocalizedStringKey {
        switch kind {
        case .pinned: "Losmaken"
        case .continuing: "Verwijderen uit Kijk verder"
        case .later: "Verwijderen uit Later kijken"
        }
    }

    private var removalSymbol: String {
        switch kind {
        case .pinned: "pin.slash"
        case .continuing: "xmark"
        case .later: "bookmark.slash"
        }
    }

    /// Saving what the tile plays, or taking it off the list: the label says
    /// which.
    @ViewBuilder
    private func saveButton(for tile: HomeTile) -> some View {
        if let toggleSave, let item = tile.saving {
            if saved.contains(item.id) {
                Button("Verwijderen uit Later kijken", systemImage: "bookmark.slash") { toggleSave(tile) }
            } else {
                Button("Later kijken", systemImage: "bookmark") { toggleSave(tile) }
            }
        }
    }

    private var empty: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text(emptyTitle)
                    .font(.body.bold())
                Text(emptyBody)
                    .foregroundStyle(.secondary)
            }
            Button("Zoeken", systemImage: "magnifyingglass", action: search)
                .accessibilityIdentifier("\(name)-empty-search")
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 24)
    }

    private var row: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 40) {
                ForEach(tiles) { tile in
                    Button { select(tile) } label: {
                        HomeTileView(tile: tile)
                    }
                    .contextMenu {
                        if let page = tile.page {
                            Button("Details", systemImage: "info.circle") { open(page) }
                        }
                        saveButton(for: tile)
                        Button(removal, systemImage: removalSymbol) { remove(tile) }
                    }
                    .accessibilityIdentifier("\(name)-\(tile.id.rawValue)")
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .buttonStyle(.card)
    }
}

/// A tile: the image of what will play, the item's title, and under it the
/// episode it continues with or that nothing is left (FR-HOME-04,
/// FR-HOME-07).
struct HomeTileView: View {
    let tile: HomeTile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: tile.artwork)
                .frame(width: CatalogueTile.width, height: CatalogueTile.width * 9 / 16)
                .clipped()
                .overlay(alignment: .bottom) { progress }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: tile.title)
                    .font(.caption)
                    .lineLimit(1)
                line
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: CatalogueTile.width, alignment: .leading)
    }

    /// How far in the episode is, when that is known (FR-HOME-06).
    @ViewBuilder private var progress: some View {
        if !tile.isUnavailable, case .continues(_, let fraction?) = tile.state {
            ProgressView(value: fraction)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        }
    }

    /// The words carry the state, not a colour or a symbol alone
    /// (NFR-A11Y-04).
    @ViewBuilder private var line: some View {
        if tile.isUnavailable {
            Label("Niet meer beschikbaar", systemImage: "exclamationmark.triangle.fill")
        } else {
            available
        }
    }

    @ViewBuilder private var available: some View {
        switch tile.state {
        case .notStarted:
            Text("Serie")
        case .continues(let next, _):
            // An episode saved from search carries its series' name as its
            // title: it is not said twice.
            Text(verbatim: tile.kind == .series && next.title != tile.title ? Self.name(of: next) : next.caption ?? "")
        case .finished:
            Label(tile.kind == .series ? Self.seriesWatched : Self.watched, systemImage: "checkmark.circle.fill")
        }
    }

    private static let seriesWatched: LocalizedStringKey = "Alle afleveringen gezien"
    private static let watched: LocalizedStringKey = "Gezien"

    /// An episode as one line: its title, and NPO's caption when it has one.
    private static func name(of episode: Upcoming) -> String {
        [episode.title, episode.caption].compactMap(\.self).joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Nothing pinned") {
    HomeRow(kind: .pinned, tiles: [], select: { _ in }, open: { _ in }, remove: { _ in }, search: {})
}

#Preview("Kijk verder") {
    HomeRow(kind: .continuing,
            tiles: [HomeTile(pinned: ScriptedCatalogue.results.series[0])],
            select: { _ in },
            open: { _ in },
            remove: { _ in },
            search: {})
}

#Preview("Tile") {
    HomeTileView(tile: HomeTile(pinned: ScriptedCatalogue.results.series[0]))
}
#endif
