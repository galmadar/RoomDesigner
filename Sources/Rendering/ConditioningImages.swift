import CoreGraphics
import simd
import UIKit

/// Turns render buffers into the pictures that get sent to the image model.
enum ConditioningImages {

    /// Which render the model is conditioned on.
    ///
    /// Worth testing against each other rather than assuming: scanned furniture
    /// arrives as bounding boxes, and that damages these three unequally.
    /// Normals suffer worst — a cuboid has six of them, so the map collapses to
    /// six flat colours. Depth suffers next. A line drawing suffers least,
    /// because box edges still read as plausible furniture silhouettes.
    enum Kind: String, CaseIterable, Identifiable {
        case depth, lines, normal
        var id: String { rawValue }
    }

    static func image(_ kind: Kind, from buffers: Renderer.Buffers) -> UIImage? {
        switch kind {
        case .depth:  return depth(buffers)
        case .normal: return normal(buffers)
        case .lines:  return lines(buffers)
        }
    }

    /// Near is bright, far is dark — the usual ControlNet depth convention.
    static func depth(_ buffers: Renderer.Buffers) -> UIImage? {
        let hit = buffers.depth.map { $0.isFinite && $0 < Float.greatestFiniteMagnitude / 2 }
        let visible = zip(buffers.depth, hit).filter(\.1).map(\.0)
        guard let low = visible.min(), let high = visible.max() else { return nil }
        let span = max(high - low, 1e-6)

        var pixels = [UInt8](repeating: 0, count: buffers.depth.count)
        for index in buffers.depth.indices where hit[index] {
            let normalised = (buffers.depth[index] - low) / span
            pixels[index] = UInt8(clamping: Int((1 - normalised) * 255))
        }
        return grayscale(pixels, width: buffers.width, height: buffers.height)
    }

    static func normal(_ buffers: Renderer.Buffers) -> UIImage? {
        rgba(buffers.normal, width: buffers.width, height: buffers.height)
    }

    /// White edges on black, wherever the room turns a corner or jumps away.
    static func lines(_ buffers: Renderer.Buffers,
                      depthJump: Float = 0.08,
                      normalTurn: Float = 0.35) -> UIImage? {
        let width = buffers.width, height = buffers.height
        var pixels = [UInt8](repeating: 0, count: width * height)

        func isHit(_ index: Int) -> Bool {
            let value = buffers.depth[index]
            return value.isFinite && value < Float.greatestFiniteMagnitude / 2
        }
        func normalAt(_ index: Int) -> SIMD3<Float> {
            let base = index * 4
            return SIMD3(Float(buffers.normal[base]) / 127.5 - 1,
                         Float(buffers.normal[base + 1]) / 127.5 - 1,
                         Float(buffers.normal[base + 2]) / 127.5 - 1)
        }

        for y in 1..<height {
            for x in 1..<width {
                let here = y * width + x
                guard isHit(here) else { continue }
                let left = here - 1, above = here - width
                guard isHit(left), isHit(above) else { pixels[here] = 255; continue }

                let jumped = abs(buffers.depth[here] - buffers.depth[left]) > depthJump
                    || abs(buffers.depth[here] - buffers.depth[above]) > depthJump
                let turned = 1 - simd_dot(normalAt(here), normalAt(left)) > normalTurn
                    || 1 - simd_dot(normalAt(here), normalAt(above)) > normalTurn

                if jumped || turned { pixels[here] = 255 }
            }
        }
        return grayscale(pixels, width: width, height: height)
    }

    // MARK: -

    private static func grayscale(_ pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        var data = pixels
        guard let provider = CGDataProvider(data: Data(bytes: &data, count: data.count) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image)
    }

    private static func rgba(_ pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        var data = pixels
        guard let provider = CGDataProvider(data: Data(bytes: &data, count: data.count) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image)
    }
}
