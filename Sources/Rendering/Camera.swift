import simd

/// A virtual camera standing inside the scanned room.
struct Camera {
    var eye: SIMD3<Float>
    var target: SIMD3<Float>
    var fieldOfView: Float = 65 * .pi / 180
    var near: Float = 0.05
    var far: Float = 40
    /// Screen-up in world space. Only a photo's viewpoint needs roll.
    var up: SIMD3<Float> = SIMD3(0, 1, 0)

    /// Standing at a chosen spot on the floor, at eye height, facing `yaw`.
    static func standing(at ground: SIMD2<Float>,
                         in bounds: (min: SIMD3<Float>, max: SIMD3<Float>),
                         eyeHeight: Float = 1.5,
                         yaw: Float = 0,
                         pitch: Float = 0,
                         fieldOfView: Float = 65 * .pi / 180) -> Camera {
        let inside = clamp(ground, in: bounds)
        let height = min(bounds.min.y + eyeHeight, bounds.max.y - 0.05)
        let eye = SIMD3(inside.x, height, inside.y)
        let direction = SIMD3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        return Camera(eye: eye, target: eye + direction, fieldOfView: fieldOfView)
    }

    /// Keeps the eye just inside the walls. Outside them you would be looking at
    /// the back of the room, which renders as a solid block.
    static func clamp(_ ground: SIMD2<Float>,
                      in bounds: (min: SIMD3<Float>, max: SIMD3<Float>),
                      margin: Float = 0.15) -> SIMD2<Float> {
        SIMD2(min(max(ground.x, bounds.min.x + margin), bounds.max.x - margin),
              min(max(ground.y, bounds.min.z + margin), bounds.max.z - margin))
    }

    /// The middle of the room, as a starting point.
    static func centre(of bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) -> SIMD2<Float> {
        let middle = (bounds.min + bounds.max) / 2
        return SIMD2(middle.x, middle.z)
    }

    func view() -> simd_float4x4 {
        var forward = target - eye
        let length = simd_length(forward)
        forward = length > 1e-6 ? forward / length : SIMD3(0, 0, -1)

        var up = simd_normalize(self.up)
        if abs(simd_dot(forward, up)) > 0.999 { up = SIMD3(0, 0, 1) }

        let right = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(right, forward)

        let rotation = simd_float4x4(
            SIMD4(right.x, trueUp.x, -forward.x, 0),
            SIMD4(right.y, trueUp.y, -forward.y, 0),
            SIMD4(right.z, trueUp.z, -forward.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(trueUp, eye), simd_dot(forward, eye), 1)
        )
        return rotation
    }

    func projection(aspect: Float) -> simd_float4x4 {
        let scaleY = 1 / tan(fieldOfView / 2)
        let scaleX = scaleY / aspect
        let range = far - near
        return simd_float4x4(
            SIMD4(scaleX, 0, 0, 0),
            SIMD4(0, scaleY, 0, 0),
            SIMD4(0, 0, -(far + near) / range, -1),
            SIMD4(0, 0, -2 * far * near / range, 0)
        )
    }
}
