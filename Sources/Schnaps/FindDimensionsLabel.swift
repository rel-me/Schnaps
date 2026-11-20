import Foundation
import MeasurementCore

enum FindDimensionsLabel {
    /// Full pinned measurements are stored as consecutive horizontal/vertical spans.
    static func pair(_ horizontal: DimensionSpan, _ vertical: DimensionSpan) -> Dimensions? {
        guard horizontal.isHorizontal, !vertical.isHorizontal,
              horizontal.start.x <= vertical.start.x, vertical.start.x <= horizontal.end.x,
              vertical.start.y <= horizontal.start.y, horizontal.start.y <= vertical.end.y else { return nil }
        return Dimensions(horizontal: horizontal, vertical: vertical)
    }

    static func text(for rect: CGRect, rounded: Bool) -> String {
        let width = MeasurementPresentation.number(rect.width, rounded: rounded)
        let height = MeasurementPresentation.number(rect.height, rounded: rounded)
        return "\(width) × \(height)"
    }

    /// The center is the axes' intersection, not the midpoint of either span.
    /// Prefer below/right, then switch quadrants to keep both axes clear at display edges.
    static func frame(at center: CGPoint, size: CGSize, in bounds: CGRect,
                      avoiding labels: [CGRect] = []) -> CGRect {
        let available = bounds.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(size.width, max(0, available.width)),
                          height: min(size.height, max(0, available.height)))
        let origins = [
            CGPoint(x: center.x + 10, y: center.y + 10),
            CGPoint(x: center.x - size.width - 10, y: center.y + 10),
            CGPoint(x: center.x + 10, y: center.y - size.height - 10),
            CGPoint(x: center.x - size.width - 10, y: center.y - size.height - 10),
        ]
        let candidates = origins.map { OverlayControlPlacement.clamped(CGRect(origin: $0, size: size), in: available) }
        func clearsAxes(_ rect: CGRect) -> Bool {
            (rect.maxX <= center.x - 8 || rect.minX >= center.x + 8)
                && (rect.maxY <= center.y - 8 || rect.minY >= center.y + 8)
        }
        return candidates.first { candidate in
            clearsAxes(candidate) && !labels.contains { $0.insetBy(dx: -3, dy: -3).intersects(candidate) }
        } ?? candidates.first(where: clearsAxes) ?? candidates[0]
    }
}
