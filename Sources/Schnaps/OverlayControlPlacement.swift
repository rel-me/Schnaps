import Foundation

/// Places a label and its close button as a single group, with room around the tool.
enum OverlayControlPlacement {
  static func frame(size: CGSize, around tool: CGRect, in bounds: CGRect,
    avoiding controls: [CGRect] = []) -> CGRect {
    let size = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
    let origins = [
      CGPoint(x: tool.minX, y: tool.minY - size.height - 8),
      CGPoint(x: tool.minX, y: tool.maxY + 8),
      CGPoint(x: tool.maxX + 8, y: tool.minY),
      CGPoint(x: tool.minX - size.width - 8, y: tool.minY),
    ]
    var candidates = origins.map { clamped(CGRect(origin: $0, size: size), in: bounds) }
    for step in 1...max(1, controls.count) {
      for direction in [-1.0, 1.0] {
        for (index, candidate) in origins.enumerated() {
          let origin = clamped(CGRect(origin: candidate, size: size), in: bounds).origin
          let horizontal = index < 2
          let offset = direction * CGFloat(step) * ((horizontal ? size.width : size.height) + 4)
          candidates.append(clamped(CGRect(x: origin.x + (horizontal ? offset : 0),
            y: origin.y + (horizontal ? 0 : offset), width: size.width, height: size.height), in: bounds))
        }
      }
    }
    func free(_ rect: CGRect) -> Bool {
      !controls.contains { $0.insetBy(dx: -3, dy: -3).intersects(rect) }
    }
    return candidates.first { !$0.intersects(tool) && free($0) }
      ?? candidates.first { !$0.intersects(tool) }
      ?? candidates.first(where: free) ?? candidates[0]
  }

  static func clamped(_ rect: CGRect, in bounds: CGRect) -> CGRect {
    let size = CGSize(width: min(rect.width, bounds.width), height: min(rect.height, bounds.height))
    return CGRect(x: max(bounds.minX, min(rect.minX, bounds.maxX - size.width)),
      y: max(bounds.minY, min(rect.minY, bounds.maxY - size.height)), width: size.width, height: size.height)
  }
}
