//
//  NPOCatalogueBodies.swift
//  NPO light
//

import Foundation

/// One of the account's NPO profiles, from `GET /profiles`.
nonisolated struct ProfileBody: Decodable {
    static let generalType = "GENERAL"
    static let kidsType = "KIDS"

    let guid: String
    let type: String?
}

/// An image as NPO lists it. `role` tells a header image (`default`) from a
/// transparent title logo (`title`).
nonisolated struct ImageBody: Decodable {
    static let artworkRole = "default"

    let url: String?
    let role: String?
}

/// How far a profile watched something, on the items NPO has a position for
/// and on no others.
nonisolated struct ProgressBody: Decodable {
    let secondsWatched: Double?
    let fractionWatched: Double?

    /// The length is the one the position was measured against, which is the
    /// stream's and not always the one a list gives.
    func position(of listed: Int?) -> SharedPosition? {
        guard let seconds = secondsWatched, seconds.isFinite, seconds > 0 else { return nil }
        var duration = listed.map(TimeInterval.init)
        if let fraction = fractionWatched, fraction.isFinite, fraction > 0 {
            duration = seconds / fraction
        }
        return SharedPosition(offset: seconds, duration: duration)
    }
}

/// An item in a collection or a season. A collection mixes types, and only the
/// fields every type shares are certain; the rest is there for some of them.
nonisolated struct CatalogueItemBody: Decodable {
    static let seriesType = "series"
    static let programType = "program"

    /// What NPO's app opens for a programme that belongs to no series: a
    /// page of its own. An episode of a series has `player` here (Q-10).
    static let singleProgrammeTarget = "detail"

    let guid: String
    /// Absent in a season's list, where everything is a programme.
    let type: String?
    let title: String?
    let subtitle: String?
    let synopsis: String?
    let durationInSeconds: Int?
    /// Only in a collection. A season's list has none.
    let target: String?
    let images: [ImageBody]?
    let progress: ProgressBody?

    var artwork: URL? {
        images?.first { $0.role == ImageBody.artworkRole }?.url.flatMap(URL.init(string:))
    }

    var seriesSummary: SeriesSummary? {
        guard let title else { return nil }
        return SeriesSummary(id: ItemID(rawValue: guid), title: title, artwork: artwork)
    }

    var playable: Playable? {
        guard let title else { return nil }
        return Playable(id: EpisodeID(rawValue: guid),
                        title: title,
                        caption: subtitle,
                        synopsis: synopsis,
                        duration: durationInSeconds.map { .seconds($0) },
                        artwork: artwork,
                        position: progress?.position(of: durationInSeconds))
    }
}

/// `GET /pages/by/slug/home`: the rows of NPO's own home page, of which one
/// is read.
nonisolated struct HomePageBody: Decodable {
    struct Collection: Decodable {
        /// What NPO calls the row a profile goes on from, whatever version
        /// of it this is: `continue-watching-v0`, `-v1`.
        static let continuingPrefix = "continue-watching"

        let guid: String?
        let items: [CatalogueItemBody]?
    }

    let collections: [Collection]

    /// The row a profile goes on from, under the name this answer gives it.
    var continuingRow: String? {
        collections.compactMap(\.guid).first { $0.hasPrefix(Collection.continuingPrefix) }
    }

    /// What the profile can go on with, in NPO's order.
    var continuing: [Continued] {
        let rows = collections.filter { $0.guid?.hasPrefix(Collection.continuingPrefix) == true }
        return rows.flatMap { $0.items ?? [] }.compactMap { item in
            guard item.type == CatalogueItemBody.programType, let playable = item.playable else { return nil }
            return Continued(playable: playable, isSingle: item.target == CatalogueItemBody.singleProgrammeTarget)
        }
    }
}

/// `GET /search`: the page envelope, with one collection of series and one of
/// programmes.
nonisolated struct SearchBody: Decodable {
    struct Collection: Decodable {
        let items: [CatalogueItemBody]?
    }

    let collections: [Collection]

    /// Sorted by each item's own type rather than by the collection it came
    /// in, so a collection NPO adds or renames does not lose results.
    ///
    /// NPO lists single programmes among the episodes. They are told apart by
    /// where NPO's app would go for them, and a programme that does not say is
    /// taken for an episode, which is what nearly all of them are.
    var results: SearchResults {
        let items = collections.flatMap { $0.items ?? [] }
        let programmes = items.filter { $0.type == CatalogueItemBody.programType }
        let singles = programmes.filter { $0.target == CatalogueItemBody.singleProgrammeTarget }
        let episodes = programmes.filter { $0.target != CatalogueItemBody.singleProgrammeTarget }
        return SearchResults(
            series: items.filter { $0.type == CatalogueItemBody.seriesType }.compactMap(\.seriesSummary),
            singleProgrammes: singles.compactMap(\.playable),
            episodes: episodes.compactMap(\.playable)
        )
    }
}

/// `GET /series/page/{guid}`: the whole series screen in one answer.
nonisolated struct SeriesPageBody: Decodable {
    struct Header: Decodable {
        let title: String
        /// NPO puts the synopsis in the header's subtitle.
        let subtitle: String?
        let images: [ImageBody]?
    }

    struct Tab: Decodable {
        static let seasonsType = "seasons"

        /// What ``programSort`` says for a programme that is followed as it
        /// is broadcast — a daily one, with a season for each year. NPO then
        /// lists the latest season first, as well as the latest episode.
        static let newestFirst = "desc"

        let type: String?
        let programSort: String?
        let seasons: [SeasonBody]?
    }

    struct SeasonBody: Decodable {
        let guid: String
        let title: String
    }

    let guid: String
    let header: Header
    let tabs: [Tab]?

    var detail: SeriesDetail {
        let tab = tabs?.first { $0.type == Tab.seasonsType }
        let seasons = tab?.seasons ?? []
        let artwork = header.images?
            .first { $0.role == ImageBody.artworkRole }?.url
            .flatMap(URL.init(string:))
        return SeriesDetail(
            id: ItemID(rawValue: guid),
            title: header.title,
            synopsis: header.subtitle,
            artwork: artwork,
            seasons: seasons.map { Season(id: SeasonID(rawValue: $0.guid), title: $0.title) },
            listsNewestFirst: tab?.programSort == Tab.newestFirst
        )
    }
}

/// `GET /programs/page/{guid}`: the page of one programme.
nonisolated struct ProgrammePageBody: Decodable {
    struct Header: Decodable {
        let title: String
        /// A short description. The long one is in the info tab.
        let subtitle: String?
        /// NPO's own line, such as `Muziek • 1u 35m`.
        let metadata: String?
        let durationInSeconds: Int?
        let images: [ImageBody]?
        let playButton: PlayButton?
        let progress: ProgressBody?
    }

    struct PlayButton: Decodable {
        let enabled: Bool?
    }

    struct Tab: Decodable {
        let synopsis: String?
    }

    let guid: String
    let header: Header
    let tabs: [Tab]?

    var detail: ProgrammeDetail {
        let artwork = header.images?
            .first { $0.role == ImageBody.artworkRole }?.url
            .flatMap(URL.init(string:))
        let synopsis = tabs?.compactMap(\.synopsis).first { !$0.isEmpty } ?? header.subtitle
        let metadata = header.metadata.flatMap { $0.isEmpty ? nil : $0 }
        return ProgrammeDetail(
            playable: Playable(id: EpisodeID(rawValue: guid),
                               title: header.title,
                               caption: metadata,
                               synopsis: synopsis,
                               duration: header.durationInSeconds.map { .seconds($0) },
                               artwork: artwork,
                               position: header.progress?.position(of: header.durationInSeconds)),
            // NPO says so on the button it would draw. Not saying is not a
            // refusal: the stream is still asked for, and may be.
            isPlayable: header.playButton?.enabled ?? true
        )
    }
}
