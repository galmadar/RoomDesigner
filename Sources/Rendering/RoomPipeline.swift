import Metal
import simd

/// The vertex layout, the uniform block and the buffer building that the
/// offscreen renderer and the live walk share, so one mesh feeds both.
enum RoomPipeline {

    struct Uniforms {
        var modelViewProjection: simd_float4x4
        var modelView: simd_float4x4
        var normalMatrix: simd_float4x4
    }

    /// Position, normal and tint, tightly interleaved in one buffer.
    static var vertexDescriptor: MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        for attribute in 0..<3 {
            descriptor.attributes[attribute].format = .float3
            descriptor.attributes[attribute].offset = MemoryLayout<SIMD3<Float>>.stride * attribute
            descriptor.attributes[attribute].bufferIndex = 0
        }
        descriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 3
        return descriptor
    }

    /// The mesh in the order `vertexDescriptor` expects.
    static func interleaved(_ mesh: Mesh) -> [SIMD3<Float>] {
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(mesh.positions.count * 3)
        for index in mesh.positions.indices {
            vertices.append(mesh.positions[index])
            vertices.append(index < mesh.normals.count ? mesh.normals[index] : SIMD3(0, 1, 0))
            vertices.append(index < mesh.colours.count ? mesh.colours[index] : Palette.wall)
        }
        return vertices
    }

    /// Built once per mesh: walking must never do this between frames.
    static func buffers(for mesh: Mesh, device: MTLDevice)
        -> (vertices: MTLBuffer, indices: MTLBuffer)? {
        let vertices = interleaved(mesh)
        guard !vertices.isEmpty, !mesh.indices.isEmpty,
              let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<SIMD3<Float>>.stride * vertices.count,
                options: .storageModeShared),
              let indexBuffer = device.makeBuffer(
                bytes: mesh.indices,
                length: MemoryLayout<UInt32>.stride * mesh.indices.count,
                options: .storageModeShared)
        else { return nil }
        return (vertexBuffer, indexBuffer)
    }

    static func depthState(_ device: MTLDevice) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)
    }
}
