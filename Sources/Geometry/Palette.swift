import simd

/// Flat colours for the solid view.
///
/// Chosen to read as a room at a glance, not to be accurate: a scan carries no
/// colour information at all, so anything here is an honest invention. What
/// matters is that floor, walls, what was scanned and what was added are each
/// instantly distinguishable.
enum Palette {
    static let floor    = SIMD3<Float>(0.72, 0.55, 0.36)   // warm oak
    static let wall     = SIMD3<Float>(0.90, 0.89, 0.86)   // off-white
    static let ceiling  = SIMD3<Float>(0.96, 0.96, 0.95)   // brighter than the walls
    static let scanned  = SIMD3<Float>(0.62, 0.64, 0.68)   // grey — RoomPlan found it
    static let proposed = SIMD3<Float>(0.42, 0.72, 0.50)   // green — you added it
}
