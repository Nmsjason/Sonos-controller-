import Foundation

public enum FixtureLoader {
    public static func householdData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "jason-household", withExtension: "json") else {
            throw SonosError.malformed("jason-household.json is missing from SonosCore resources")
        }
        return try Data(contentsOf: url)
    }

    public static func loadSnapshot() throws -> HouseholdSnapshot {
        try JSONDecoder().decode(HouseholdSnapshot.self, from: householdData())
    }

    public static func loadSnapshotOrEmpty() -> HouseholdSnapshot {
        (try? loadSnapshot()) ?? .empty
    }

    public static func spotifySearchData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "spotify-search", withExtension: "json") else {
            throw SonosError.malformed("spotify-search.json is missing from SonosCore resources")
        }
        return try Data(contentsOf: url)
    }
}

extension HouseholdSnapshot {
    static var empty: HouseholdSnapshot {
        HouseholdSnapshot(
            household: Household(id: "Sonos_empty", name: "Home", players: [], groups: [], presets: [], favorites: []),
            peers: [],
            catalog: [],
            profile: Profile(name: "Jason", initials: "JS")
        )
    }
}
