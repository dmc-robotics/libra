import LibraKit
import MetalKit

/// Matches `Uniforms` in Shaders.swift.
private struct Uniforms {
    var viewProjection: simd_float4x4
    var color: SIMD4<Float>
    var viewDirection: SIMD3<Float>
    var depthOffset: Float
}

/// Draws a `ViewerScene` in three passes: shaded faces, edge lines, then markers on top.
@MainActor
final class Renderer: NSObject, MTKViewDelegate {
    /// Depth (0…1 of the clip range) that edge lines are pulled toward the viewer.
    private static let lineDepthOffset: Float = 2e-5

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let facePipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let markerPipeline: MTLRenderPipelineState
    private let modelDepth: MTLDepthStencilState
    private let overlayDepth: MTLDepthStencilState
    private var partBuffers: [UUID: PartBuffers] = [:]

    init?(view: MTKView) {
        guard let device = view.device,
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Shaders.source, options: nil) else { return nil }
        self.device = device
        self.commandQueue = commandQueue

        func pipeline(_ vertex: String, _ fragment: String, blended: Bool = false) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            if blended {
                let attachment = descriptor.colorAttachments[0]!
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            descriptor.rasterSampleCount = view.sampleCount
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let facePipeline = pipeline("faceVertex", "faceFragment"),
              let linePipeline = pipeline("lineVertex", "lineFragment"),
              let markerPipeline = pipeline("markerVertex", "markerFragment", blended: true) else { return nil }
        self.facePipeline = facePipeline
        self.linePipeline = linePipeline
        self.markerPipeline = markerPipeline

        let model = MTLDepthStencilDescriptor()
        model.depthCompareFunction = .lessEqual
        model.isDepthWriteEnabled = true
        let overlay = MTLDepthStencilDescriptor()
        overlay.depthCompareFunction = .always
        overlay.isDepthWriteEnabled = false
        guard let modelDepth = device.makeDepthStencilState(descriptor: model),
              let overlayDepth = device.makeDepthStencilState(descriptor: overlay) else { return nil }
        self.modelDepth = modelDepth
        self.overlayDepth = overlayDepth
        super.init()
    }

    /// Uploads parts not seen before and drops ones that are gone.
    func load(_ parts: [ViewerPart]) {
        let ids = Set(parts.map(\.id))
        partBuffers = partBuffers.filter { ids.contains($0.key) }
        for part in parts where partBuffers[part.id] == nil {
            partBuffers[part.id] = PartBuffers(device: device, geometry: part.geometry)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let viewer = view as? ViewerMTKView,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let scene = viewer.scene
        let camera = viewer.camera
        var uniforms = Uniforms(
            viewProjection: camera.viewProjectionMatrix, color: .zero, viewDirection: SIMD3<Float>(camera.back), depthOffset: 0
        )
        let uniformsLength = MemoryLayout<Uniforms>.stride

        // Faces. The slope bias pushes faces back at grazing angles so their edges stay visible.
        encoder.setDepthStencilState(modelDepth)
        encoder.setRenderPipelineState(facePipeline)
        encoder.setCullMode(.none)
        encoder.setDepthBias(0, slopeScale: 1, clamp: 0)
        func drawTriangles(_ buffers: PartBuffers, color: SIMD4<Float>, triangles: Range<Int>? = nil) {
            uniforms.color = color
            encoder.setVertexBuffer(buffers.positions, offset: 0, index: 0)
            encoder.setVertexBuffer(buffers.normals, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 2)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            let range = triangles ?? 0..<(buffers.indexCount / 3)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: range.count * 3, indexType: .uint32,
                indexBuffer: buffers.indices, indexBufferOffset: range.lowerBound * 3 * MemoryLayout<UInt32>.stride
            )
        }
        for part in scene.parts {
            if let buffers = partBuffers[part.id] {
                drawTriangles(buffers, color: part.color)
            }
        }
        if let face = scene.highlightedFace,
           let buffers = partBuffers[face.partID],
           let geometry = scene.parts.first(where: { $0.id == face.partID })?.geometry,
           geometry.faces.indices.contains(face.index) {
            // Same depth as the face itself, so lessEqual lets it through
            drawTriangles(buffers, color: scene.highlightColor, triangles: geometry.faces[face.index].triangleRange)
        }

        // Edges
        encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
        encoder.setRenderPipelineState(linePipeline)
        uniforms.color = ViewerStyle.edgeColor
        uniforms.depthOffset = Self.lineDepthOffset
        for part in scene.parts {
            guard let buffers = partBuffers[part.id], let edges = buffers.edgeVertices else { continue }
            encoder.setVertexBuffer(edges, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 2)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: buffers.edgeVertexCount)
        }

        // Markers, always on top
        let markers = MarkerMesh(markers: scene.markers, camera: camera, highlightColor: scene.highlightColor).vertices
        if !markers.isEmpty, let buffer = PartBuffers.buffer(device, markers) {
            encoder.setDepthStencilState(overlayDepth)
            encoder.setRenderPipelineState(markerPipeline)
            uniforms.depthOffset = 0
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: markers.count)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
