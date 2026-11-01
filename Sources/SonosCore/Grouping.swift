import Foundation

extension Household {
    /// Rebuild groups so `playerIds` play together. The first id is the coordinator.
    /// Playback is taken from the coordinator's previous group. Rooms that fall out of a group
    /// and are left uncovered become idle solo groups.
    public func regrouping(_ playerIds: [String]) -> Household {
        var household = self
        let ids = uniquePreservingOrder(playerIds).filter { player(id: $0) != nil }
        guard let coordinator = ids.first else { return household }

        let seed = groups.first { $0.playerIds.contains(coordinator) }
        let playback = seed?.playback ?? .idle
        let volume = seed?.volume ?? Volume(value: 25)

        var remaining: [PlayerGroup] = []
        for group in groups {
            var next = group
            next.playerIds.removeAll { ids.contains($0) }
            guard !next.playerIds.isEmpty else { continue }
            if !next.playerIds.contains(next.coordinatorId) {
                next.coordinatorId = next.playerIds[0]
                next.id = next.coordinatorId
            }
            next.name = household.makeGroupName(coordinatorId: next.coordinatorId, playerIds: next.playerIds)
            remaining.append(next)
        }

        let grouped = PlayerGroup(
            id: coordinator,
            name: makeGroupName(coordinatorId: coordinator, playerIds: ids),
            coordinatorId: coordinator,
            playerIds: ids,
            volume: volume,
            playback: playback
        )
        remaining.removeAll { $0.id == grouped.id }
        remaining.append(grouped)

        let covered = Set(remaining.flatMap(\.playerIds))
        for player in players where !covered.contains(player.id) {
            remaining.append(
                PlayerGroup(
                    id: player.id,
                    name: player.name,
                    coordinatorId: player.id,
                    playerIds: [player.id],
                    volume: player.volume,
                    playback: .idle
                )
            )
        }

        remaining.sort { lhs, rhs in
            let left = player(id: lhs.coordinatorId)?.sortOrder ?? 0
            let right = player(id: rhs.coordinatorId)?.sortOrder ?? 0
            return left < right
        }
        household.groups = remaining
        return household
    }

    public func makeGroupName(coordinatorId: String, playerIds: [String]) -> String {
        let names = playerIds.map { player(id: $0)?.name ?? $0 }
        guard let lead = names.first else { return "" }
        let extras = names.dropFirst()
        if extras.isEmpty { return lead }
        if extras.count == 1, let other = extras.first { return "\(lead) + \(other)" }
        return "\(lead) + \(extras.count)"
    }

    func updatingGroup(_ groupId: String, _ body: (inout PlayerGroup) -> Void) -> Household {
        var household = self
        guard let index = household.groups.firstIndex(where: { $0.id == groupId }) else { return household }
        body(&household.groups[index])
        return household
    }

    func updatingPlayer(_ playerId: String, _ body: (inout Player) -> Void) -> Household {
        var household = self
        guard let index = household.players.firstIndex(where: { $0.id == playerId }) else { return household }
        body(&household.players[index])
        return household
    }
}

func uniquePreservingOrder(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    return ids.filter { seen.insert($0).inserted }
}
