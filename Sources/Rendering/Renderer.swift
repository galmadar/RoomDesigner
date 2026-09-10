import Metal
import MetalKit
import simd

/// Renders the room offscreen to the buffers an image model gets conditioned on.
///
/// Metal directly, rather than RealityKit: `RealityRenderer` is genuinely
/// headless but its `CameraOutput` exposes only colour textures, with no way to
/// bind a depth attachment — and depth is exactly what we need.
final class Renderer {

    struct Buffers {
        let width: Int
        let height: Int
        /// Metres from the camera. `.infinity` where nothing was hit.
        let depth: [Float]
        /// Camera-space normals, already mapped into 0...1, RGBA order.
        let normal: [UInt8]
        /// The room drawn as a room: flat colours with a simple headlight.
        let solid: [UInt8]

        func depthAt(x: Int, y: Int) -> Float { depth[y * width + x] }
    }

    enum Failure: Error {
        case noMetalDevice
        case shaderLibraryMissing
        case emptyMesh
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw Failure.noMetalDevice }
        self.device = device
        self.queue = queue

        guard let library = try? device.makeDefaultLibrary(bundle: .main),
              let vertexFunction = library.makeFunction(name: "room_vertex"),
              let fragmentFunction = library.makeFunction(name: "room_fragment")
        else { throw Failure.shaderLibraryMissing }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float3
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 3

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm      // normals
        descriptor.colorAttachments[1].pixelFormat = .r32Float        // linear depth
        descriptor.colorAttachments[2].pixelFormat = .rgba8Unorm      // the room, shaded
        descriptor.depthAttachmentPixelFormat = .depth32Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw Failure.noMetalDevice
        }
        depthState = state
    }

    func render(_ mesh: Mesh, camera: Camera, size: Int = 768) throws -> Buffers {
        guard !mesh.isEmpty else { throw Failure.emptyMesh }

        // Interleave once; the vertex descriptor above expects position+normal.
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(mesh.positions.count * 3)
        for index in mesh.positions.indices {
            vertices.append(mesh.positions[index])
            vertices.append(index < mesh.normals.count ? mesh.normals[index] : SIMD3(0, 1, 0))
            vertices.append(index < mesh.colours.count ? mesh.colours[index] : Palette.wall)
        }

        guard let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<SIMD3<Float>>.stride * vertices.count,
                options: .storageModeShared),
              let indexBuffer = device.makeBuffer(
                bytes: mesh.indices,
                length: MemoryLayout<UInt32>.stride * mesh.indices.count,
                options: .storageModeShared)
        else { throw Failure.emptyMesh }

        let normalTexture = makeTexture(format: .rgba8Unorm, size: size)
        let depthTexture = makeTexture(format: .r32Float, size: size)
        let solidTexture = makeTexture(format: .rgba8Unorm, size: size)
        let zBuffer = makeTexture(format: .depth32Float, size: size, readable: false)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = normalTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[1].texture = depthTexture
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].storeAction = .store
        // Cleared to "infinitely far", so untouched pixels read as no geometry.
        pass.colorAttachments[1].clearColor = MTLClearColor(red: Double(Float.greatestFiniteMagnitude),
                                                            green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[2].texture = solidTexture
        pass.colorAttachments[2].loadAction = .clear
        pass.colorAttachments[2].storeAction = .store
        pass.colorAttachments[2].clearColor = MTLClearColor(red: 0.05, green: 0.05,
                                                            blue: 0.06, alpha: 1)
        pass.depthAttachment.texture = zBuffer
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1.0

        let view = camera.view()
        var uniforms = Uniforms(
            modelViewProjection: camera.projection(aspect: 1) * view,
            modelView: view,
            normalMatrix: view
        )

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else { throw Failure.noMetalDevice }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        // Standing inside the room means seeing the far side of every surface,
        // so nothing may be culled.
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: mesh.indices.count,
                                      indexType: .uint32,
                                      indexBuffer: indexBuffer,
                                      indexBufferOffset: 0)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return Buffers(width: size, height: size,
                       depth: readFloats(depthTexture, size: size),
                       normal: readBytes(normalTexture, size: size),
                       solid: readBytes(solidTexture, size: size))
    }

    // MARK: -

    private struct Uniforms {
        var modelViewProjection: simd_float4x4
        var modelView: simd_float4x4
        var normalMatrix: simd_float4x4
    }

    private func makeTexture(format: MTLPixelFormat, size: Int,
                             readable: Bool = true) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = readable ? .shared : .private
        return device.makeTexture(descriptor: descriptor)!
    }

    private func readFloats(_ texture: MTLTexture, size: Int) -> [Float] {
        var out = [Float](repeating: 0, count: size * size)
        out.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!,
                             bytesPerRow: size * MemoryLayout<Float>.size,
                             from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        }
        return out
    }

    private func readBytes(_ texture: MTLTexture, size: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size * size * 4)
        out.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: size * 4,
                             from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        }
        return out
    }
}
