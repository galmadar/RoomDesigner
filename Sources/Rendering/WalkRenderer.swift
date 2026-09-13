import MetalKit
import QuartzCore
import simd

/// Draws the scanned room live, from wherever you are standing in it.
///
/// Everything costly happens once, at init: the pipeline, the depth state and
/// the mesh's buffers. A frame is then three matrices, a `setVertexBytes` and
/// one indexed draw — no mesh work, no allocation, nothing to wait on.
@MainActor
final class WalkRenderer: NSObject, MTKViewDelegate {

    static let colourFormat = MTLPixelFormat.bgra8Unorm
    static let depthFormat = MTLPixelFormat.depth32Float
    /// A room is all long straight edges, and on Apple GPUs the resolve stays in
    /// tile memory. Dropped to 1 if the device will not have it.
    static let wantedSamples = 4

    /// Asked for the camera once a frame, given the seconds since the last one.
    var pose: ((Float) -> Camera)?

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var vertices: MTLBuffer
    private var indices: MTLBuffer
    private var indexCount: Int
    private let sampleCount: Int
    private var lastFrame: CFTimeInterval?

    init?(mesh: Mesh) {
        guard !mesh.isEmpty,
              let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .main),
              let vertexFunction = library.makeFunction(name: "room_vertex"),
              let fragmentFunction = library.makeFunction(name: "room_walk_fragment"),
              let buffers = RoomPipeline.buffers(for: mesh, device: device),
              let depthState = RoomPipeline.depthState(device)
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = RoomPipeline.vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = Self.colourFormat
        descriptor.depthAttachmentPixelFormat = Self.depthFormat

        var built: (state: MTLRenderPipelineState, samples: Int)?
        for samples in [Self.wantedSamples, 1] where built == nil {
            guard samples == 1 || device.supportsTextureSampleCount(samples) else { continue }
            descriptor.rasterSampleCount = samples
            if let state = try? device.makeRenderPipelineState(descriptor: descriptor) {
                built = (state, samples)
            }
        }
        guard let built else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = built.state
        self.sampleCount = built.samples
        self.depthState = depthState
        self.vertices = buffers.vertices
        self.indices = buffers.indices
        self.indexCount = mesh.indices.count
        super.init()
    }

    func configure(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = Self.colourFormat
        view.depthStencilPixelFormat = Self.depthFormat
        view.sampleCount = sampleCount
        view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.isOpaque = true
        // A 3× drawable costs 2¼× the fragments of a 2× one, for detail nobody
        // can see on a wall of flat colour at arm's length.
        view.contentScaleFactor = min(view.window?.screen.scale ?? 2, 2)
    }

    /// Swaps the room's geometry for another layout of it. Main-actor, like
    /// `draw`, so a frame can never read one buffer against the other's count.
    func replace(mesh: Mesh) {
        guard let buffers = RoomPipeline.buffers(for: mesh, device: device) else { return }
        vertices = buffers.vertices
        indices = buffers.indices
        indexCount = mesh.indices.count
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pose,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        // Clamped, so a stall or a trip through the background cannot teleport you.
        let now = CACurrentMediaTime()
        let elapsed = Float(min(max(now - (lastFrame ?? now), 0), 1.0 / 15))
        lastFrame = now

        let size = view.drawableSize
        let aspect = size.height > 0 ? Float(size.width / size.height) : 1
        let camera = pose(elapsed)
        let viewMatrix = camera.view()
        var uniforms = RoomPipeline.Uniforms(
            modelViewProjection: camera.projection(aspect: aspect) * viewMatrix,
            modelView: viewMatrix,
            normalMatrix: viewMatrix
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        // Standing inside the room means seeing the far side of every surface,
        // so nothing may be culled.
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RoomPipeline.Uniforms>.stride,
                               index: 1)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount,
                                      indexType: .uint32, indexBuffer: indices,
                                      indexBufferOffset: 0)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
