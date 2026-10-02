import Foundation

/// A frame that can be edited: the Libra frame, a body's frame, or the frame a part's override values are entered in.
public enum FrameTarget: Hashable, Sendable {
    case libra
    case body(UUID)
    case override(UUID)
}

/// Every change to a document goes through these, so its rules live in one place:
/// a part belongs to at most one body, and bodies list their parts in document order.
extension LibraDocument {
    public func body(_ id: UUID) -> Body? {
        bodies.first { $0.id == id }
    }

    // MARK: Frames

    public func frame(for target: FrameTarget) -> Frame? {
        switch target {
        case .libra:
            libraFrame
        case .body(let id):
            body(id)?.frame
        case .override(let id):
            if case .override(let values) = part(id)?.mass { values.frame } else { nil }
        }
    }

    public mutating func setFrame(_ frame: Frame, for target: FrameTarget) {
        switch target {
        case .libra:
            libraFrame = frame
        case .body(let id):
            guard let index = bodies.firstIndex(where: { $0.id == id }) else { return }
            bodies[index].frame = frame
        case .override(let id):
            guard let index = parts.firstIndex(where: { $0.id == id }),
                  case .override(var values) = parts[index].mass else { return }
            values.frame = frame
            parts[index].mass = .override(values)
        }
    }

    // MARK: Bodies

    /// Makes a body from `partIDs`, taking them out of any other body. The frame starts as the Libra frame.
    /// Returns nil (and changes nothing) if none of the IDs are parts of this document.
    @discardableResult
    public mutating func createBody(named name: String? = nil, partIDs: some Sequence<UUID>) -> UUID? {
        let members = orderedPartIDs(partIDs)
        guard !members.isEmpty else { return nil }
        removeFromBodies(Set(members))
        let body = Body(name: name ?? nextBodyName(), partIDs: members, frame: libraFrame)
        bodies.append(body)
        return body.id
    }

    /// Moves parts into a body, taking them out of any other body.
    public mutating func addParts(_ partIDs: some Sequence<UUID>, toBody bodyID: UUID) {
        guard bodies.contains(where: { $0.id == bodyID }) else { return }
        let moving = Set(orderedPartIDs(partIDs))
        removeFromBodies(moving)
        let index = bodies.firstIndex { $0.id == bodyID }!
        let members = Set(bodies[index].partIDs).union(moving)
        bodies[index].partIDs = orderedPartIDs(members)
    }

    public mutating func removeFromBodies(_ partIDs: Set<UUID>) {
        for index in bodies.indices {
            bodies[index].partIDs.removeAll(where: partIDs.contains)
        }
    }

    public mutating func deleteBody(_ id: UUID) {
        bodies.removeAll { $0.id == id }
    }

    /// The body a part is in, if any.
    public func body(containing partID: UUID) -> Body? {
        bodies.first { $0.partIDs.contains(partID) }
    }

    private func orderedPartIDs(_ ids: some Sequence<UUID>) -> [UUID] {
        let wanted = Set(ids)
        return parts.map(\.id).filter(wanted.contains)
    }

    private func nextBodyName() -> String {
        let names = Set(bodies.map(\.name))
        var number = bodies.count + 1
        while names.contains("Body \(number)") {
            number += 1
        }
        return "Body \(number)"
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
