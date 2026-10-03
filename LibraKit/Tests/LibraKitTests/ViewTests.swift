@testable import LibraKit
import Testing
import simd

@Suite struct CameraTests {
    let box = Fixtures.boxPart(size: [0.1, 0.2, 0.3], corner: [1, 1, 1])

    func camera(_ view: StandardView) -> OrthographicCamera {
        var camera = OrthographicCamera(viewportSize: [800, 600], sceneBounds: box.geometry.bounds)
        camera.look(from: view, in: .file)
        camera.fit(box.geometry.bounds)
        return camera
    }

    @Test func centerOfViewportPicksTheFacingFace() throws {
        let picker = PartPicker(parts: [box])
        // From each standard view, the middle of the screen hits the face whose normal points at the viewer
        let expectedNormals: [StandardView: SIMD3<Double>] = [
            .front: [0, -1, 0], .back: [0, 1, 0], .left: [-1, 0, 0], .right: [1, 0, 0], .top: [0, 0, 1], .bottom: [0, 0, -1]
        ]
        for (view, normal) in expectedNormals {
            let camera = camera(view)
            let hit = try #require(picker.pick(camera.ray(through: [400, 300])), "\(view)")
            let face = try #require(hit.face)
            expectClose(box.geometry.faces[face].direction, normal)
        }
    }

    @Test func projectIsInverseOfRay() {
        let camera = camera(.isometric)
        let point = SIMD2<Double>(123, 456)
        let ray = camera.ray(through: point)
        expectClose(camera.project(ray.point(at: 0.37)), point)
    }

    @Test func fitKeepsBoundsInsideViewport() {
        for view in StandardView.allCases {
            let camera = camera(view)
            for corner in box.geometry.bounds.corners {
                let screen = camera.project(corner)
                #expect(screen.x >= 0 && screen.x <= 800 && screen.y >= 0 && screen.y <= 600, "\(view) \(screen)")
            }
        }
    }

    @Test func zoomKeepsPointUnderCursor() {
        var camera = camera(.front)
        let cursor = SIMD2<Double>(600, 150)
        let before = camera.pointOnViewPlane(cursor)
        camera.zoom(by: 0.5, at: cursor)
        expectClose(camera.pointOnViewPlane(cursor), before)
        #expect(camera.worldPerPoint < self.camera(.front).worldPerPoint)
    }

    @Test func panMovesModelWithCursor() {
        var camera = camera(.top)
        let point = SIMD3<Double>(1.05, 1.1, 1.3)
        let before = camera.project(point)
        camera.pan(by: [30, -20])
        expectClose(camera.project(point), before + [30, -20])
    }

    @Test func orbitKeepsPivotFixedOnScreen() {
        var camera = camera(.isometric)
        let pivot = SIMD3<Double>(1.1, 1.2, 1.3)
        let before = camera.project(pivot)
        camera.orbit(by: [40, 25], around: pivot, upAxis: [0, 0, 1])
        expectClose(camera.project(pivot), before)
    }

    @Test func depthOfModelIsInsideClipRange() {
        let camera = camera(.isometric)
        let matrix = camera.viewProjectionMatrix
        for corner in box.geometry.bounds.corners {
            let clip = matrix * SIMD4<Float>(SIMD3<Float>(corner), 1)
            #expect(clip.z > 0 && clip.z < 1)
        }
    }
}

@Suite struct SnapperTests {
    let box = Fixtures.boxPart(size: [0.1, 0.1, 0.1])

    func setUp(cursorAt point: SIMD3<Double>) throws -> (Snapper, PickHit) {
        var camera = OrthographicCamera(viewportSize: [800, 600], sceneBounds: box.geometry.bounds)
        camera.look(from: .top, in: .file)
        camera.fit(box.geometry.bounds)
        let cursor = camera.project(point)
        let hit = try #require(PartPicker(parts: [box]).pick(camera.ray(through: cursor)))
        return (Snapper(camera: camera, cursor: cursor), hit)
    }

    @Test func middleOfPlanarFaceSnapsToItsCenter() throws {
        let (snapper, hit) = try setUp(cursorAt: [0.03, 0.06, 0.1])
        let snap = try #require(snapper.originSnap(for: hit, in: box.geometry))
        #expect(snap.kind == .faceCenter)
        expectClose(snap.point, [0.05, 0.05, 0.1], tolerance: 1e-6)
    }

    @Test func nearCornerSnapsToVertex() throws {
        let (snapper, hit) = try setUp(cursorAt: [0.099, 0.099, 0.1])
        let snap = try #require(snapper.originSnap(for: hit, in: box.geometry))
        #expect(snap.kind == .vertex)
        expectClose(snap.point, [0.1, 0.1, 0.1], tolerance: 1e-6)
    }

    @Test func directionFromFaceAndEdge() throws {
        let (faceSnapper, faceHit) = try setUp(cursorAt: [0.05, 0.05, 0.1])
        let normal = try #require(faceSnapper.directionSnap(for: faceHit, in: box.geometry))
        #expect(normal.kind == .faceNormal)
        expectClose(try #require(normal.direction), [0, 0, 1])

        let (edgeSnapper, edgeHit) = try setUp(cursorAt: [0.05, 0.099, 0.1])
        let edge = try #require(edgeSnapper.directionSnap(for: edgeHit, in: box.geometry))
        #expect(edge.kind == .lineDirection)
        expectClose(abs(try #require(edge.direction).x), 1, tolerance: 1e-6)
    }
}

@Suite struct MarkerMeshTests {
    let camera = OrthographicCamera(viewportSize: [800, 600], sceneBounds: Fixtures.boxPart(size: [1, 1, 1], corner: .zero).geometry.bounds)
    let highlight: SIMD4<Float> = [1, 0, 1, 1]

    func colors(_ marker: Marker) -> [SIMD4<Float>] {
        MarkerMesh(markers: [marker], camera: camera, highlightColor: highlight).vertices.map(\.color)
    }

    /// How far the triad reaches from its origin, in points.
    func reach(_ size: TriadSize) -> Double {
        let positions = MarkerMesh(markers: [.triad(.file, size: size, selected: false)], camera: camera, highlightColor: highlight)
            .vertices.map { SIMD3<Double>($0.position) }
        return positions.map(simd_length).max()! / camera.worldPerPoint
    }

    @Test func smallTriadsAreShorter() {
        #expect(abs(reach(.large) - MarkerMesh.Style.triadLength) < 1e-3)
        #expect(abs(reach(.small) - MarkerMesh.Style.smallTriadLength) < 1e-3)
    }

    @Test func selectedFrameGlowsInTheHighlightColor() {
        let plain = colors(.triad(.file, size: .large, selected: false))
        #expect(!plain.contains { $0.x == highlight.x && $0.y == highlight.y && $0.z == highlight.z })
        #expect(plain.allSatisfy { $0.w == 1 })

        let selected = colors(.triad(.file, size: .large, selected: true))
        #expect(selected.contains(highlight))
        #expect(selected.contains([1, 0, 1, MarkerMesh.Style.selectedGlowOpacity]))
        #expect(selected.contains([1, 0, 1, 0]))
    }
}

@Suite struct TooltipRegionTests {
    @Test func tooltipsAtTheSameSpotShareARegion() {
        var camera = OrthographicCamera(viewportSize: [800, 600], sceneBounds: Fixtures.boxPart(size: [1, 1, 1]).geometry.bounds)
        camera.look(from: .front, in: .file)
        camera.fit(Fixtures.boxPart(size: [1, 1, 1]).geometry.bounds)
        let regions = TooltipRegion.regions(for: [
            ViewerTooltip(point: .zero, radius: 8, text: "Libra frame"),
            ViewerTooltip(point: [1, 0, 1], radius: 8, text: "Arm frame"),
            ViewerTooltip(point: .zero, radius: 10, text: "Base frame")
        ], camera: camera)
        #expect(regions.count == 2)
        #expect(regions[0].text == "Libra frame\nBase frame")
        #expect(regions[0].radius == 10)
        expectClose(regions[0].center, camera.project(.zero))
        #expect(regions[1].text == "Arm frame")
    }
}
