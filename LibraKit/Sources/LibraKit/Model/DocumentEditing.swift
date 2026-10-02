import Foundation

/// A frame that can be edited: the Libra frame, a group's frame, or the frame a part's override values are entered in.
public enum FrameTarget: Hashable, Sendable {
    case libra
    case group(UUID)
    case override(UUID)
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
        case .override(let id):
            if case .override(let values) = part(id)?.mass { values.frame } else { nil }
        }
    }

    public mutating func setFrame(_ frame: Frame, for target: FrameTarget) {
        switch target {
        case .libra:
            libraFrame = frame
        case .group(let id):
            guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
            groups[index].frame = frame
        case .override(let id):
            guard let index = parts.firstIndex(where: { $0.id == id }),
                  case .override(var values) = parts[index].mass else { return }
            values.frame = frame
            parts[index].mass = .override(values)
        }
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

    public mutating func setMass(_ assignment: MassAssignment, forParts partIDs: Set<UUID>) {
        for index in parts.indices where partIDs.contains(parts[index].id) {
            parts[index].mass = assignment
        }
    }

    /// Switches how a part gets its mass, carrying over what it has: a measured mass keeps the current mass,
    /// and an override starts from the current properties expressed in the Libra frame.
    public mutating func changeMassKind(of partID: UUID, to kind: MassAssignment.Kind) {
        guard let index = parts.firstIndex(where: { $0.id == partID }), parts[index].mass.kind != kind else { return }
        let part = parts[index]
        let current = part.massProperties
        switch kind {
        case .unassigned:
            parts[index].mass = .unassigned
        case .measured:
            parts[index].mass = .measured(current?.mass ?? 0)
        case .override:
            let local = current?.expressed(in: libraFrame)
            parts[index].mass = .override(MassOverride(
                mass: local?.mass ?? 0,
                centerOfMass: local?.centerOfMass ?? libraFrame.localPoint(part.volumeProperties.centroid),
                inertia: local?.inertia ?? .zero,
                frame: libraFrame
            ))
        }
    }
}
