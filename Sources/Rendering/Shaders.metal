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
    float3 tint     [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float3 tint;
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
    out.tint   = in.tint;
    return out;
}

struct FragmentOut {
    float4 normal [[color(0)]];
    float  depth  [[color(1)]];
    float4 solid  [[color(2)]];
};

// Flip on the normal itself rather than on triangle winding. Standing inside a
// room, winding says nothing useful about which way a wall faces — and getting
// it wrong leaves every surface unlit, because the light and the camera are the
// same direction.
static inline float3 room_facing_normal(float3 normal)
{
    float3 facing = normalize(normal);
    return facing.z < 0.0 ? -facing : facing;
}

// A headlight, plus enough ambient that walls facing away still read.
// Deliberately plain: a scan carries no colour or lighting, so anything fancier
// would be inventing detail rather than showing the room.
static inline float3 room_shade(float3 normal, float3 tint)
{
    float lambert = saturate(dot(normal, float3(0.0, 0.0, 1.0)));
    float shade   = 0.45 + 0.55 * lambert;
    return saturate(tint * shade);
}

fragment FragmentOut room_fragment(VertexOut in [[stage_in]])
{
    float3 normal = room_facing_normal(in.normal);

    FragmentOut out;
    out.normal = float4(normal * 0.5 + 0.5, 1.0);
    out.depth  = in.viewDepth;
    out.solid  = float4(room_shade(normal, in.tint), 1.0);
    return out;
}

/// The same room, the same shading, straight to a drawable: walking through it
/// should look like the still it is drawn from, not like a second renderer.
fragment float4 room_walk_fragment(VertexOut in [[stage_in]])
{
    return float4(room_shade(room_facing_normal(in.normal), in.tint), 1.0);
}
