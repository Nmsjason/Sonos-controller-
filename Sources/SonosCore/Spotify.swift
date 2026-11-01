import Foundation

/// Spotify Web API search and browse. Sonos still does the playing.
public enum SpotifyWebAPI {
    public static func searchURL(query: String, limit: Int = 20) -> URL? {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track,album,playlist,artist"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }

    public static func decodeSearch(_ data: Data) throws -> [CatalogItem] {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        var items: [CatalogItem] = []
        items += tracks(root["tracks"])
        items += playlists(root["playlists"])
        items += albums(root["albums"])
        items += artists(root["artists"])
        return items
    }

    private static func tracks(_ value: JSONValue?) -> [CatalogItem] {
        guard let rows = value?["items"]?.array else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"]?.string, let id = row["id"]?.string else { return nil }
            let artist = row["artists"]?.array?.first?["name"]?.string ?? ""
            let album = row["album"]?["name"]?.string ?? ""
            return CatalogItem(
                id: id,
                title: name,
                subtitle: [artist, album].filter { !$0.isEmpty }.joined(separator: " · "),
                source: .spotify,
                kind: .track,
                art: .placeholder(for: .spotify),
                spotifyURI: row["uri"]?.string
            )
        }
    }

    private static func playlists(_ value: JSONValue?) -> [CatalogItem] {
        guard let rows = value?["items"]?.array else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"]?.string, let id = row["id"]?.string else { return nil }
            let owner = row["owner"]?["display_name"]?.string ?? "Playlist"
            return CatalogItem(
                id: id,
                title: name,
                subtitle: "Playlist · \(owner)",
                source: .spotify,
                kind: .playlist,
                art: .placeholder(for: .spotify),
                spotifyURI: row["uri"]?.string
            )
        }
    }

    private static func albums(_ value: JSONValue?) -> [CatalogItem] {
        guard let rows = value?["items"]?.array else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"]?.string, let id = row["id"]?.string else { return nil }
            let artist = row["artists"]?.array?.first?["name"]?.string ?? "Album"
            return CatalogItem(
                id: id,
                title: name,
                subtitle: "Album · \(artist)",
                source: .spotify,
                kind: .album,
                art: .placeholder(for: .spotify),
                spotifyURI: row["uri"]?.string
            )
        }
    }

    private static func artists(_ value: JSONValue?) -> [CatalogItem] {
        guard let rows = value?["items"]?.array else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"]?.string, let id = row["id"]?.string else { return nil }
            return CatalogItem(
                id: id,
                title: name,
                subtitle: "Artist",
                source: .spotify,
                kind: .track,
                art: .placeholder(for: .spotify),
                spotifyURI: row["uri"]?.string
            )
        }
    }
}
