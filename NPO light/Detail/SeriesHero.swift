//
//  SeriesHero.swift
//  NPO light
//

import SwiftUI

/// The series' own image from edge to edge, fading into the page, with the
/// title, the description and the actions on it (FR-CONTENT-03,
/// FR-CONTENT-08, FR-HOME-03).
struct SeriesHero: View {
    private enum Action: Hashable {
        case play
        case pin
    }

    let title: String
    let detail: SeriesDetail?
    let fallbackArtwork: URL?

    /// What the main action plays, when there is something to play.
    let primary: SeriesDetailModel.Primary?
    let isFullyWatched: Bool
    let isPinned: Bool
    let play: () -> Void
    let togglePin: () -> Void

    /// Focus came to one of the actions.
    let focused: () -> Void

    @FocusState private var focus: Action?

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
        .onChange(of: focus) { _, focus in
            if focus != nil { focused() }
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
            continuation
                .padding(.top, 12)
            HStack(spacing: 24) {
                if let primary {
                    Button(primary.resumes ? Self.resume : Self.start, systemImage: "play.fill", action: play)
                        .focused($focus, equals: .play)
                        .accessibilityValue(Text(verbatim: Self.name(of: primary.episode)))
                        .accessibilityIdentifier(primary.resumes ? "series-resume" : "series-play")
                }
                pin
            }
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .padding(.horizontal, 80)
        .padding(.bottom, 40)
    }

    private static let start: LocalizedStringKey = "Afspelen"
    private static let resume: LocalizedStringKey = "Verder kijken"

    /// An episode as one line: its title, and NPO's caption when it has one.
    private static func name(of episode: Playable) -> String {
        [episode.title, episode.caption].compactMap(\.self).joined(separator: " · ")
    }

    /// Which episode the main action plays, or that there is none left.
    @ViewBuilder private var continuation: some View {
        if isFullyWatched {
            Label("Alle afleveringen gezien", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .accessibilityIdentifier("series-watched")
        } else if let primary {
            Text(verbatim: Self.name(of: primary.episode))
                .font(.callout)
                .lineLimit(1)
        }
    }

    /// The words say which of the two it does, not only the symbol
    /// (NFR-A11Y-04).
    @ViewBuilder private var pin: some View {
        if isPinned {
            Button("Losmaken", systemImage: "pin.slash", action: togglePin)
                .focused($focus, equals: .pin)
                .accessibilityIdentifier("series-unpin")
        } else {
            Button("Vastzetten", systemImage: "pin", action: togglePin)
                .focused($focus, equals: .pin)
                .accessibilityIdentifier("series-pin")
        }
    }
}

#if DEBUG
#Preview("Hero") {
    SeriesHero(title: "Freeks wilde wereld",
               detail: nil,
               fallbackArtwork: nil,
               primary: .init(episode: ScriptedCatalogue.results.episodes[0],
                              season: ScriptedCatalogue.seasons[0].id,
                              resumes: true),
               isFullyWatched: false,
               isPinned: false,
               play: {},
               togglePin: {},
               focused: {})
}
#endif
