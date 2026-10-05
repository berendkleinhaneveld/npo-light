//
//  SubtitledManifest.swift
//  NPO light
//

import Foundation

/// NPO's manifest with its subtitles added (ADR 0027).
///
/// NPO delivers subtitles as one WebVTT file beside the stream, and the
/// stream's own manifest names none. The system player only offers what the
/// manifest names, so the app hands it a manifest that does: NPO's own, with
/// a subtitle rendition for each file, and a playlist of one segment for
/// each rendition.
nonisolated enum SubtitledManifest {
    /// The scheme the system player cannot fetch by itself, so that it asks
    /// the app for the manifest instead.
    static let scheme = "npo-light"

    /// The address the player is given in place of NPO's manifest.
    static let manifest = address(host: "manifest", file: "master.m3u8")

    private static let group = "subtitles"
    private static let subtitlesHost = "subtitles"

    /// The address of the playlist for the track at `index`.
    static func playlistAddress(for index: Int) -> URL? {
        address(host: subtitlesHost, file: "\(index).m3u8")
    }

    /// Which track a playlist address is for, or `nil` when it is not one.
    static func trackIndex(of address: URL) -> Int? {
        guard address.scheme == scheme, address.host() == subtitlesHost else { return nil }
        return Int(address.deletingPathExtension().lastPathComponent)
    }

    private static func address(host: String, file: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + file
        return components.url
    }

    /// NPO's manifest, naming `tracks` as subtitles of every variant.
    ///
    /// The manifest is no longer at NPO's address, so everything it names
    /// relative to itself is named in full.
    static func multivariant(_ original: String, from base: URL, adding tracks: [SubtitleTrack]) -> String {
        var lines: [String] = []
        var renditionsAdded = false
        for line in original.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("#EXT-X-STREAM-INF"), !renditionsAdded {
                lines += renditions(for: tracks)
                renditionsAdded = true
            }
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                lines.append(line + ",SUBTITLES=\"\(group)\"")
            } else if line.hasPrefix("#") {
                lines.append(absolute(attributesOf: line, from: base))
            } else {
                lines.append(URL(string: line, relativeTo: base)?.absoluteString ?? line)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renditions(for tracks: [SubtitleTrack]) -> [String] {
        tracks.indices.compactMap { index in
            guard let address = playlistAddress(for: index) else { return nil }
            let track = tracks[index]
            // A quote would end the attribute early.
            let name = track.name.replacing("\"", with: "")
            let language = track.language.replacing("\"", with: "")
            return "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(group)\",NAME=\"\(name)\",LANGUAGE=\"\(language)\","
                + "AUTOSELECT=YES,DEFAULT=NO,FORCED=NO,URI=\"\(address.absoluteString)\""
        }
    }

    /// A tag whose `URI` is relative to the manifest, with it named in full.
    /// One that has a scheme already — a key's — is left as it is.
    private static func absolute(attributesOf line: String, from base: URL) -> String {
        guard let range = line.range(of: #"URI="[^"]*""#, options: .regularExpression) else { return line }
        let uri = String(line[range].dropFirst(5).dropLast())
        guard let resolved = URL(string: uri, relativeTo: base)?.absoluteString else { return line }
        return line.replacingCharacters(in: range, with: "URI=\"\(resolved)\"")
    }

    /// A playlist of the one file a track is: the whole programme in one
    /// segment, from the start.
    static func playlist(for track: SubtitleTrack, lasting duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:\(Int(seconds.rounded(.up)))
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:\(String(format: "%.3f", seconds)),
        \(track.location.absoluteString)
        #EXT-X-ENDLIST

        """
    }
}
