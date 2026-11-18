import AppKit
import MeasurementCore

typealias DesignDisplay = (id: UInt32, bounds: CGRect)

extension CGRect {
  func desktopPoint(from point: CGPoint) -> CGPoint {
    CGPoint(x: minX + point.x, y: maxY - point.y)
  }

  func displayPoint(from point: CGPoint) -> CGPoint {
    CGPoint(x: point.x - minX, y: maxY - point.y)
  }
}

extension DesignMarker {
  /// Marker coordinates use the owning display's top-left, in logical points.
  func projected(from source: CGRect, to target: CGRect) -> DesignMarker {
    var result = self
    result.x += source.minX - target.minX
    result.y += target.maxY - source.maxY
    return result
  }

  func projection(on target: DesignDisplay, from source: CGRect, in bounds: CGRect) -> DesignMarker? {
    if display == target.id { return self }
    if tool == .guides { return nil }
    let projected = projected(from: source, to: target.bounds)
    return tool == .ruler || projected.rect.intersects(bounds) ? projected : nil
  }

  func reanchored(from source: CGRect, on displays: [DesignDisplay], pointer: CGPoint) -> DesignMarker {
    let destinationID: UInt32?
    switch tool {
    case .ruler:
      let origin = source.desktopPoint(from: rect.origin)
      destinationID = displays.first { $0.bounds.contains(origin) }?.id
    case .guides:
      destinationID = displays.first { $0.bounds.contains(pointer) }?.id
    default:
      let topLeft = source.desktopPoint(from: rect.origin)
      let desktopRect = CGRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height)
      destinationID = DesignGeometry.bestDisplay(for: desktopRect, displays: displays)
    }
    guard let destination = displays.first(where: { $0.id == destinationID }), destination.id != display
    else { return self }
    var marker = projected(from: source, to: destination.bounds)
    marker.display = destination.id
    if tool == .guides {
      // A guide can be grabbed from a label offset from its line.
      if vertical { marker.x = min(max(0, marker.x), destination.bounds.width - 1) }
      else { marker.y = min(max(0, marker.y), destination.bounds.height - 1) }
    }
    marker.validate()
    return marker
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
