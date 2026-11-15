import AppKit
import MeasurementCore

extension DesignMarker {
  /// Marker coordinates use the owning display's top-left, in logical points.
  func projected(from source: CGRect, to target: CGRect) -> DesignMarker {
    var result = self
    result.x += source.minX - target.minX
    result.y += target.maxY - source.maxY
    return result
  }

  func containsEditingPoint(_ point: CGPoint) -> Bool {
    switch tool {
    case .ruler:
      let start = CGPoint(x: x, y: y)
      if DesignGeometry.distance(point, toSegmentFrom: start, to: end) < 24 { return true }
      if calipers {
        for endpoint in [start, end] {
          let a = DesignGeometry.endpoint(origin: endpoint, length: 70, degrees: angle + 90)
          let b = DesignGeometry.endpoint(origin: endpoint, length: 70, degrees: angle - 90)
          if DesignGeometry.distance(point, toSegmentFrom: a, to: b) < 10 { return true }
        }
      }
      if square {
        let corner = DesignGeometry.endpoint(origin: start, length: height, degrees: angle + 90)
        let far = DesignGeometry.endpoint(origin: corner, length: width, degrees: angle)
        return DesignGeometry.distance(point, toSegmentFrom: start, to: corner) < 10
          || DesignGeometry.distance(point, toSegmentFrom: corner, to: far) < 10
      }
      return false
    case .guides:
      return abs(vertical ? point.x - x : point.y - y) < 14
    default:
      return rect.insetBy(dx: -8, dy: -8).contains(point)
    }
  }
}
