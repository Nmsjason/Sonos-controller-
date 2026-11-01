import Foundation
import Observation

/// UI-facing session over the mock controller. iOS and watchOS both hold one of these.
@MainActor
@Observable
public final class SonosSession {
    public private(set) var snapshot: HouseholdSnapshot
    public private(set) var lastError: String?
    private let controller: MockSonosController

    public init(snapshot: HouseholdSnapshot? = nil) {
        let loaded = snapshot ?? FixtureLoader.loadSnapshotOrEmpty()
        self.snapshot = loaded
        self.controller = MockSonosController(snapshot: loaded)
    }

    public var household: Household { snapshot.household }
    public var profile: Profile { snapshot.profile }

    public var featuredGroup: PlayerGroup? { household.featuredGroup }

    public func group(_ id: String) -> PlayerGroup? { household.group(id: id) }

    public func sections(for source: MusicSource) -> [CatalogSection] {
        snapshot.sections(for: source)
    }

    public func search(source: MusicSource, query: String) -> [CatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = sections(for: source).flatMap(\.items)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public func peers(in groupId: String) -> [SessionPeer] {
        snapshot.peers(in: groupId)
    }

    public func start() async {
        snapshot = await controller.snapshot()
        let stream = await controller.updates()
        for await next in stream {
            snapshot = next
        }
    }

    public func perform(_ command: ControllerCommand) async {
        do {
            try await controller.perform(command)
            snapshot = await controller.snapshot()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
