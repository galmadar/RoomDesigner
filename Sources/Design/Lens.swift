import Foundation

/// How wide the view is, in the one vocabulary the app says it in.
///
/// Three screens let you open the lens up and every one of them should say the
/// same four things about it. What they cannot share is the numbers: the walk's
/// angle runs down a full-screen portrait frame, the scan screen's runs across
/// a square, and the design shot's runs across a 4:3 landscape — so the same
/// degrees frame different pictures. Each carries its own range and its own
/// band edges rather than borrowing the walk's.
struct Lens {
    /// Narrowest and widest the frame is allowed, in radians.
    let range: ClosedRange<Float>
    /// Degrees at which "tight" turns to "natural", "natural" to "wide", and
    /// "wide" to "very wide".
    let edges: (natural: Float, wide: Float, veryWide: Float)

    func words(_ fieldOfView: Float) -> String {
        let degrees = fieldOfView * 180 / .pi
        if degrees < edges.natural { return "tight, picks out one corner" }
        if degrees < edges.wide { return "natural, like your eyes" }
        if degrees < edges.veryWide { return "wide, more of the room at once" }
        return "very wide, the edges stretch"
    }

    func clamped(_ fieldOfView: Float) -> Float {
        min(max(fieldOfView, range.lowerBound), range.upperBound)
    }

    static func degrees(_ radians: Float) -> Int { Int((radians * 180 / .pi).rounded()) }

    private static func radians(_ degrees: Float) -> Float { degrees * .pi / 180 }

    /// Down a full-screen portrait frame. Wider than 100° bends a wall you are
    /// standing close to badly enough that the room stops reading as square.
    static let walk = Lens(range: radians(50)...radians(100), edges: (60, 76, 92))

    /// Across the square the scan screen draws, which is the whole frame the
    /// renderer produces — nothing is cropped away, so the number is the width
    /// and the height at once.
    static let square = Lens(range: radians(30)...radians(110), edges: (45, 75, 95))

    /// Across the 4:3 landscape the design flow cuts its picture from.
    ///
    /// The renderer draws a square and `PhotoDesignScene.freeShot` keeps its
    /// full width and the middle three quarters of its height, so this number
    /// is the finished picture's width: 65° across is about a 28 mm lens, 40°
    /// about a 50 mm, 100° about a 15 mm. Tighter than 40° stops reading as a
    /// photograph of a room and starts reading as a detail of one. The wide end
    /// matches the walk's, and bends walls less at it: 100° across a frame this
    /// shape is 83° down it, where the walk's 100° is 100° down a taller one.
    static let shot = Lens(range: radians(40)...radians(100), edges: (50, 72, 88))
}
