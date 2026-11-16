import Foundation

/// Shared by manual areas and areas selected with Find Dimensions.
enum AreaMeasurementLabel {
    static func frame(for area: CGRect, size: CGSize, in bounds: CGRect, avoiding labels: [CGRect]) -> CGRect {
        let available = bounds.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(size.width, max(0, available.width)),
                          height: min(size.height, max(0, available.height)))
        let origins = [
            CGPoint(x: area.midX - size.width / 2, y: area.maxY + 10),
            CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 6),
            CGPoint(x: area.maxX + 10, y: area.minY),
            CGPoint(x: area.minX - size.width - 10, y: area.minY),
        ]
        var candidates = origins.map { OverlayControlPlacement.clamped(CGRect(origin: $0, size: size), in: available) }
        for step in 1...max(1, labels.count) {
            for direction in [-1.0, 1.0] {
                for (index, candidate) in origins.enumerated() {
                    let origin = OverlayControlPlacement.clamped(CGRect(origin: candidate, size: size), in: available).origin
                    let horizontal = index < 2
                    let offset = direction * CGFloat(step) * ((horizontal ? size.width : size.height) + 4)
                    candidates.append(OverlayControlPlacement.clamped(
                        CGRect(x: origin.x + (horizontal ? offset : 0), y: origin.y + (horizontal ? 0 : offset),
                               width: size.width, height: size.height), in: available))
                }
            }
        }
        func free(_ rect: CGRect) -> Bool { !labels.contains { $0.insetBy(dx: -3, dy: -3).intersects(rect) } }
        return candidates.first { !$0.intersects(area) && free($0) }
            ?? candidates.first(where: free) ?? candidates[0]
    }
}
