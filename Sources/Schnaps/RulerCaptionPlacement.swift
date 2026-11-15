import CoreGraphics
import Foundation

/// Keeps the entire caption control group on one side of the ruler's 36-point band.
enum RulerCaptionPlacement {
  static func rect(preferred: CGRect, origin: CGPoint, angle: Double, bounds: CGRect) -> CGRect {
    let radians = angle * .pi / 180
    let normal = CGPoint(x: -sin(radians), y: cos(radians))
    let radius = abs(normal.x) * preferred.width / 2 + abs(normal.y) * preferred.height / 2
    let clearance = radius + 22
    func distance(_ rect: CGRect) -> CGFloat {
      (rect.midX - origin.x) * normal.x + (rect.midY - origin.y) * normal.y
    }
    func clamped(_ rect: CGRect) -> CGRect {
      CGRect(x: max(bounds.minX, min(bounds.maxX - rect.width, rect.minX)),
        y: max(bounds.minY, min(bounds.maxY - rect.height, rect.minY)),
        width: rect.width, height: rect.height)
    }
    var candidates = [clamped(preferred)]
    for side in [-1.0, 1.0] {
      let offset = side * clearance - distance(preferred)
      candidates.append(clamped(preferred.offsetBy(dx: normal.x * offset, dy: normal.y * offset)))
    }
    // Edge candidates provide a clear fallback when clamping a normal offset crosses the ruler.
    for x in [preferred.minX, bounds.minX, bounds.maxX - preferred.width] {
      for y in [preferred.minY, bounds.minY, bounds.maxY - preferred.height] {
        candidates.append(clamped(CGRect(origin: CGPoint(x: x, y: y), size: preferred.size)))
      }
    }
    let ordered = candidates.sorted {
      hypot($0.minX - preferred.minX, $0.minY - preferred.minY)
        < hypot($1.minX - preferred.minX, $1.minY - preferred.minY)
    }
    return ordered.first { abs(distance($0)) >= clearance - 0.000001 }
      ?? candidates.max { abs(distance($0)) < abs(distance($1)) }!
  }
}
