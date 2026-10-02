/// Metal shader source, compiled when the viewer starts (no Metal Toolchain needed at build time).
enum Shaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // Must match `Uniforms` in Renderer.swift
    struct Uniforms {
        float4x4 viewProjection;
        float4 color;
        float3 viewDirection;   // toward the viewer
        float depthOffset;      // pulls lines in front of the faces they lie on
    };

    struct FaceOut {
        float4 position [[position]];
        float3 normal;
    };

    vertex FaceOut faceVertex(uint id [[vertex_id]],
                              const device float3 *positions [[buffer(0)]],
                              const device float3 *normals [[buffer(1)]],
                              constant Uniforms &uniforms [[buffer(2)]]) {
        FaceOut out;
        out.position = uniforms.viewProjection * float4(positions[id], 1);
        out.normal = normals[id];
        return out;
    }

    // Flat CAD shading: a headlight, lit from both sides so reversed faces don't go black
    fragment float4 faceFragment(FaceOut in [[stage_in]], constant Uniforms &uniforms [[buffer(0)]]) {
        float facing = abs(dot(normalize(in.normal), uniforms.viewDirection));
        float shade = 0.45 + 0.55 * facing;
        return float4(uniforms.color.rgb * shade, uniforms.color.a);
    }

    struct LineOut {
        float4 position [[position]];
    };

    vertex LineOut lineVertex(uint id [[vertex_id]],
                              const device float3 *positions [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(2)]]) {
        LineOut out;
        out.position = uniforms.viewProjection * float4(positions[id], 1);
        out.position.z -= uniforms.depthOffset;
        return out;
    }

    fragment float4 lineFragment(LineOut in [[stage_in]], constant Uniforms &uniforms [[buffer(0)]]) {
        return uniforms.color;
    }

    // Must match `MarkerVertex` in LibraKit
    struct MarkerVertex {
        float3 position;
        float4 color;
    };

    struct MarkerOut {
        float4 position [[position]];
        float4 color;
    };

    vertex MarkerOut markerVertex(uint id [[vertex_id]],
                                  const device MarkerVertex *vertices [[buffer(0)]],
                                  constant Uniforms &uniforms [[buffer(2)]]) {
        MarkerOut out;
        out.position = uniforms.viewProjection * float4(vertices[id].position, 1);
        out.color = vertices[id].color;
        return out;
    }

    fragment float4 markerFragment(MarkerOut in [[stage_in]]) {
        return in.color;
    }
    """
}
