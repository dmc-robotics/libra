import Foundation

/// A frame that can be edited: the Libra frame or a group's frame.
public enum FrameTarget: Hashable, Sendable {
    case libra
    case group(UUID)
}

/// Every change to a document goes through these, so its rules live in one place:
/// a part belongs to at most one group, and groups list their parts in document order.
extension LibraDocument {
    public func group(_ id: UUID) -> PartGroup? {
        groups.first { $0.id == id }
    }

    // MARK: Frames

    public func frame(for target: FrameTarget) -> Frame? {
        switch target {
        case .libra:
            libraFrame
        case .group(let id):
            group(id)?.frame
        }
    }

    public mutating func setFrame(_ frame: Frame, for target: FrameTarget) {
        switch target {
        case .libra:
            libraFrame = frame
        case .group(let id):
            guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
            groups[index].frame = frame
        }
    }

    /// Whether the viewer draws a frame even when it isn't being edited. The Libra frame always shows.
    public func showsFrame(_ target: FrameTarget) -> Bool {
        switch target {
        case .libra:
            true
        case .group(let id):
            group(id)?.showsFrame ?? false
        }
    }

    public mutating func setShowsFrame(_ shows: Bool, for target: FrameTarget) {
        switch target {
        case .libra:
            break
        case .group(let id):
            guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
            groups[index].showsFrame = shows
        }
    }

    /// The frames the viewer draws when none is being edited: the Libra frame, then shown group frames.
    public var shownFrameTargets: [FrameTarget] {
        let candidates = [FrameTarget.libra] + groups.map { .group($0.id) }
        return candidates.filter(showsFrame)
    }

    // MARK: Groups

    /// Makes a group from `partIDs`, taking them out of any other group. The frame starts as the Libra frame.
    /// Returns nil (and changes nothing) if none of the IDs are parts of this document.
    @discardableResult
    public mutating func createGroup(named name: String? = nil, partIDs: some Sequence<UUID>) -> UUID? {
        let members = orderedPartIDs(partIDs)
        guard !members.isEmpty else { return nil }
        removeFromGroups(Set(members))
        let group = PartGroup(name: name ?? nextGroupName(), partIDs: members, frame: libraFrame)
        groups.append(group)
        return group.id
    }

    /// Moves parts into a group, taking them out of any other group.
    public mutating func addParts(_ partIDs: some Sequence<UUID>, toGroup groupID: UUID) {
        guard groups.contains(where: { $0.id == groupID }) else { return }
        let moving = Set(orderedPartIDs(partIDs))
        removeFromGroups(moving)
        let index = groups.firstIndex { $0.id == groupID }!
        let members = Set(groups[index].partIDs).union(moving)
        groups[index].partIDs = orderedPartIDs(members)
    }

    public mutating func removeFromGroups(_ partIDs: Set<UUID>) {
        for index in groups.indices {
            groups[index].partIDs.removeAll(where: partIDs.contains)
        }
    }

    public mutating func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
    }

    /// The group a part is in, if any.
    public func group(containing partID: UUID) -> PartGroup? {
        groups.first { $0.partIDs.contains(partID) }
    }

    private func orderedPartIDs(_ ids: some Sequence<UUID>) -> [UUID] {
        let wanted = Set(ids)
        return parts.map(\.id).filter(wanted.contains)
    }

    private func nextGroupName() -> String {
        let names = Set(groups.map(\.name))
        var number = groups.count + 1
        while names.contains("Group \(number)") {
            number += 1
        }
        return "Group \(number)"
    }

    // MARK: Mass

    /// Sets the mass, in kg, of each of the parts.
    public mutating func setMass(_ mass: Double, forParts partIDs: Set<UUID>) {
        for index in parts.indices where partIDs.contains(parts[index].id) {
            parts[index].mass = mass
        }
    }
}
