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
    }

    let kind: Kind
    let tiles: [HomeTile]
    let select: (HomeTile) -> Void
    let open: (SeriesSummary) -> Void
    let remove: (ItemID) -> Void
    let search: () -> Void

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
        }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .pinned: "Vastgezet"
        case .continuing: "Kijk verder"
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch kind {
        case .pinned: "Nog niets vastgezet."
        case .continuing: "Nog niets bekeken."
        }
    }

    private var emptyBody: LocalizedStringKey {
        switch kind {
        case .pinned: "Zoek een serie en zet hem vast. Dan staat hij hier, met de volgende aflevering klaar."
        case .continuing: "Wat je gaat kijken, komt hier te staan. Zoek iets om te beginnen."
        }
    }

    private var removal: LocalizedStringKey {
        switch kind {
        case .pinned: "Losmaken"
        case .continuing: "Verwijderen uit Kijk verder"
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
                        if let series = tile.series {
                            Button("Details", systemImage: "info.circle") { open(series) }
                        }
                        Button(removal, systemImage: kind == .pinned ? "pin.slash" : "xmark") { remove(tile.id) }
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
        if case .continues(_, let fraction?) = tile.state {
            ProgressView(value: fraction)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        }
    }

    /// The words carry the state, not a colour or a symbol alone
    /// (NFR-A11Y-04).
    @ViewBuilder private var line: some View {
        switch tile.state {
        case .notStarted:
            Text("Serie")
        case .continues(let next, _):
            Text(verbatim: tile.kind == .series ? Self.name(of: next) : next.caption ?? "")
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
