#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 modelViewProjection;
    float4x4 modelView;
    float4x4 normalMatrix;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float  viewDepth;
};

vertex VertexOut room_vertex(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    float4 local = float4(in.position, 1.0);
    out.position  = uniforms.modelViewProjection * local;
    out.viewDepth = -(uniforms.modelView * local).z;

    float3x3 rotation = float3x3(uniforms.normalMatrix[0].xyz,
                                 uniforms.normalMatrix[1].xyz,
                                 uniforms.normalMatrix[2].xyz);
    out.normal = rotation * in.normal;
    return out;
}

struct FragmentOut {
    float4 normal [[color(0)]];
    float  depth  [[color(1)]];
};

fragment FragmentOut room_fragment(VertexOut in [[stage_in]],
                                   bool isFrontFacing [[front_facing]])
{
    // The camera stands inside the room, so most of what it sees is the back
    // of the geometry. Flipping away-facing normals keeps them meaningful
    // instead of leaving half the frame pointing into the walls.
    float3 normal = normalize(in.normal);
    if (!isFrontFacing) { normal = -normal; }

    FragmentOut out;
    out.normal = float4(normal * 0.5 + 0.5, 1.0);
    out.depth  = in.viewDepth;
    return out;
}
