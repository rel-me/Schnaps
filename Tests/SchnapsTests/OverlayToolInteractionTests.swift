import AppKit
import MeasurementCore
import Testing
@testable import Schnaps

@MainActor
private func mouse(_ type: NSEvent.EventType, at point: CGPoint, in view: NSView,
  modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
  try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
    modifierFlags: modifiers, timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
}

@Test(arguments: [DesignTool.ruler, .guides, .frames, .overlay, .screens]) @MainActor
func everyMarkerHasVisibleGrabbableControlsAtDisplayEdges(tool: DesignTool) throws {
  let screen = try #require(NSScreen.main)
  let name = "Schnaps.AllControls.Tests." + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let state = DesignTools(defaults: defaults)
  state.editing = true
  state.visible = true
  let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
  let canvas = DesignCanvas(frame: bounds, screen: screen, state: state)
  for point in [CGPoint(x: 2, y: 2), CGPoint(x: 798, y: 2),
    CGPoint(x: 2, y: 598), CGPoint(x: 798, y: 598), CGPoint(x: -100, y: -100)] {
    for vertical in [false, true] {
      var marker = DesignMarker(tool: tool, display: DesignTools.displayID(screen))
      marker.x = point.x
      marker.y = point.y
      marker.vertical = vertical
      state.markers = [marker]
      // A ruler whose origin is on another display has its controls on the owning canvas.
      if tool == .ruler && !bounds.contains(point) { continue }
      let label = try #require(canvas.markerLabelRect(for: marker))
      let button = try #require(canvas.removeButtonRect(for: marker))
      #expect(bounds.contains(label.union(button)))
      let center = CGPoint(x: label.midX, y: label.midY)
      #expect(canvas.cursor(at: center) === NSCursor.openHand)
      #expect(canvas.editableMarker(at: center)?.id == marker.id)
      state.markers[0].locked = true
      #expect(canvas.cursor(at: center) == nil)
      #expect(canvas.removeButtonRect(for: state.markers[0]) == nil)
      state.markers[0].locked = false
      state.markers[0].isVisible = false
      #expect(canvas.editableMarker(at: center) == nil)
      state.markers[0].isVisible = true
      state.editing = false
      #expect(canvas.cursor(at: center) == nil)
      state.editing = true
    }
  }
}

@Test @MainActor func labelsWinOverOtherToolsAndSecondaryLabelsMoveTheirOwner() throws {
  let screen = try #require(NSScreen.main)
  let name = "Schnaps.LabelPriority.Tests." + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let state = DesignTools(defaults: defaults)
  state.editing = true
  state.visible = true
  var screenMarker = DesignMarker(tool: .screens, display: DesignTools.displayID(screen))
  screenMarker.topInset = 59
  var covering = DesignMarker(tool: .frames, display: screenMarker.display)
  covering.x = 0; covering.y = 0; covering.width = 800; covering.height = 600
  state.markers = [screenMarker, covering]
  let canvas = DesignCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600), screen: screen, state: state)
  let panel = NSPanel(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
  panel.isReleasedWhenClosed = false
  panel.contentView = canvas
  defer { panel.close() }
  for label in canvas.markerLabelRects(for: screenMarker) {
    let point = CGPoint(x: label.midX, y: label.midY)
    #expect(canvas.editableMarker(at: point)?.id == screenMarker.id)
    #expect(canvas.cursor(at: point) === NSCursor.openHand)
  }
  let usable = try #require(canvas.markerLabelRects(for: screenMarker).last)
  let start = CGPoint(x: usable.midX, y: usable.midY)
  canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: canvas))
  let end = CGPoint(x: start.x + 30, y: start.y + 40)
  canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: canvas))
  canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: canvas))
  #expect(state.markers[0].x == screenMarker.x + 30)
  #expect(state.markers[0].y == screenMarker.y + 40)
  #expect(state.markers[0].width == screenMarker.width)
  #expect(state.markers[1] == covering)
}

@Test(arguments: [DesignTool.loupe, .crosshair]) @MainActor
func floatingToolLabelsDragAndClose(tool: DesignTool) throws {
  let screen = try #require(NSScreen.main)
  let name = "Schnaps.FloatingControls.Tests." + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let state = DesignTools(defaults: defaults)
  state.editing = true
  state.loupe = tool == .loupe
  state.crosshair = tool == .crosshair
  let global = CGPoint(x: screen.frame.minX + 200, y: screen.frame.maxY - 200)
  if tool == .loupe { state.frozenLoupe = global } else { state.frozenCrosshair = global }
  let canvas = DesignCanvas(frame: CGRect(origin: .zero, size: screen.frame.size), screen: screen, state: state)
  let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
  panel.isReleasedWhenClosed = false
  panel.contentView = canvas
  defer { panel.close() }
  let label = canvas.floatingLabelRect(tool)
  #expect(canvas.bounds.contains(label.union(canvas.floatingCloseRect(tool))))
  let start = CGPoint(x: label.midX, y: label.midY)
  #expect(canvas.cursor(at: start) === NSCursor.openHand)
  canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: canvas))
  #expect(canvas.cursor(at: start) === NSCursor.closedHand)
  let end = CGPoint(x: start.x - 60, y: start.y + 40)
  canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: canvas))
  canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: canvas))
  #expect((tool == .loupe ? state.frozenLoupe : state.frozenCrosshair) == CGPoint(x: global.x - 60, y: global.y - 40))
  let movedLabel = canvas.floatingLabelRect(tool)
  #expect(abs(movedLabel.minX - label.minX + 60) < 0.001)
  #expect(abs(movedLabel.minY - label.minY - 40) < 0.001)
  state.editing = false
  #expect(canvas.cursor(at: CGPoint(x: movedLabel.midX, y: movedLabel.midY)) == nil)
  state.editing = true
  let close = canvas.floatingCloseRect(tool)
  let point = CGPoint(x: close.midX, y: close.midY)
  #expect(canvas.cursor(at: point) === NSCursor.pointingHand)
  canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, in: canvas))
  #expect(!(tool == .loupe ? state.loupe : state.crosshair))
  #expect(!canvas.isDragging)
}

@Test(arguments: [false, true]) @MainActor
func measurementAreaLabelsDragAndClose(inFindMode: Bool) throws {
  let view = MeasurementView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1,
    snapshot: nil, mode: inFindMode ? .findDimensions : .area)
  let panel = NSPanel(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
  panel.isReleasedWhenClosed = false
  panel.contentView = view
  defer { panel.close() }
  let first = CGRect(x: 100, y: 100, width: 160, height: 100)
  let other = CGRect(x: 500, y: 400, width: 100, height: 100)
  view.pinned = [first, other]
  let control = try #require(view.labelControls().first)
  let start = CGPoint(x: control.label.midX, y: control.label.midY)
  #expect(view.interactionCursor(at: start) === NSCursor.openHand)
  view.mouseDown(with: try mouse(.leftMouseDown, at: start, in: view))
  let end = CGPoint(x: start.x + 30, y: start.y + 40)
  view.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: view))
  #expect(view.interactionCursor(at: end) === NSCursor.closedHand)
  view.mouseUp(with: try mouse(.leftMouseUp, at: end, in: view))
  #expect(view.selection == first.offsetBy(dx: 30, dy: 40))
  #expect(view.pinned == [other])
  let active = try #require(view.labelControls().first { $0.target == .selection })
  let close = CGPoint(x: active.close.midX, y: active.close.midY)
  #expect(view.interactionCursor(at: close) === NSCursor.pointingHand)
  view.mouseDown(with: try mouse(.leftMouseDown, at: close, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: close, in: view))
  #expect(view.selection == nil)
  #expect(view.pinned == [other])
}

@Test(arguments: [false, true]) @MainActor
func pinnedDistanceLabelsMoveAndCloseOnlyTheirSpans(paired: Bool) throws {
  let view = MeasurementView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1,
    snapshot: nil, mode: .findDimensions)
  let horizontal = DimensionSpan(start: CGPoint(x: 100, y: 150), end: CGPoint(x: 300, y: 150))
  let vertical = DimensionSpan(start: CGPoint(x: 200, y: 100), end: CGPoint(x: 200, y: 250))
  let other = DimensionSpan(start: CGPoint(x: 500, y: 400), end: CGPoint(x: 600, y: 400))
  let spans = paired ? [horizontal, vertical] : [horizontal]
  view.pinnedDistances = spans + [other]
  let control = try #require(view.labelControls().first)
  let start = CGPoint(x: control.label.midX, y: control.label.midY)
  view.mouseDown(with: try mouse(.leftMouseDown, at: start, in: view))
  let end = CGPoint(x: start.x + 20, y: start.y + 30)
  view.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: end, in: view))
  #expect(view.pinnedDistances.first?.start == CGPoint(x: 120, y: 180))
  #expect(view.pinnedDistances.last == other)
  let moved = try #require(view.labelControls().first)
  let close = CGPoint(x: moved.close.midX, y: moved.close.midY)
  view.mouseDown(with: try mouse(.leftMouseDown, at: close, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: close, in: view))
  #expect(view.pinnedDistances == [other])
}

@Test @MainActor func measurementGuidesHaveDraggableLabelsAndCloseButtons() throws {
  let view = MeasurementView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1,
    snapshot: nil, mode: .area)
  // Shift-H adds a horizontal guide through the current pointer.
  view.mouseMoved(with: try mouse(.mouseMoved, at: CGPoint(x: 300, y: 200), in: view))
  let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift],
    timestamp: 0, windowNumber: 0, context: nil, characters: "H", charactersIgnoringModifiers: "h",
    isARepeat: false, keyCode: 4))
  view.keyDown(with: key)
  let control = try #require(view.labelControls().first)
  let start = CGPoint(x: control.label.midX, y: control.label.midY)
  view.mouseDown(with: try mouse(.leftMouseDown, at: start, in: view))
  view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: start.x, y: start.y + 40), in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: start, in: view))
  let moved = try #require(view.labelControls().first)
  #expect(moved.text.contains("240"))
  #expect(view.selection == nil)
  let close = CGPoint(x: moved.close.midX, y: moved.close.midY)
  view.mouseDown(with: try mouse(.leftMouseDown, at: close, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: close, in: view))
  #expect(view.labelControls().isEmpty)
}

@Test func rulerExtensionsCanBeGrabbedAndCombinedDimensionsClearBothAxes() {
  var marker = DesignMarker(tool: .ruler, display: 0)
  marker.calipers = true
  #expect(marker.containsEditingPoint(CGPoint(x: 100, y: 160)))
  marker.calipers = false
  marker.square = true
  #expect(marker.containsEditingPoint(CGPoint(x: 200, y: 340)))
  let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
  for point in [CGPoint(x: 2, y: 2), CGPoint(x: 798, y: 598), CGPoint(x: 798, y: 2), CGPoint(x: 2, y: 598)] {
    let frame = FindDimensionsLabel.frame(at: point, size: CGSize(width: 160, height: 28), in: bounds)
    #expect(bounds.insetBy(dx: 8, dy: 8).contains(frame))
    #expect(frame.maxX <= point.x - 8 || frame.minX >= point.x + 8)
    #expect(frame.maxY <= point.y - 8 || frame.minY >= point.y + 8)
  }
}

@Test @MainActor func grabbedMeasurementKeepsOtherSelectionsAndResizeHandlesWork() throws {
  let view = MeasurementView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1,
    snapshot: nil, mode: .area)
  let first = CGRect(x: 100, y: 100, width: 100, height: 100)
  let second = CGRect(x: 400, y: 300, width: 100, height: 100)
  view.pinned = [first, second]
  func clickLabel(_ target: MeasurementView.ControlTarget) throws {
    let control = try #require(view.labelControls().first { $0.target == target })
    let point = CGPoint(x: control.label.midX, y: control.label.midY)
    view.mouseDown(with: try mouse(.leftMouseDown, at: point, in: view))
    view.mouseUp(with: try mouse(.leftMouseUp, at: point, in: view))
  }
  try clickLabel(.area(0))
  #expect(view.selection == first)
  try clickLabel(.area(0))
  #expect(view.selection == second)
  #expect(view.pinned == [first])
  let corner = CGPoint(x: second.maxX, y: second.maxY)
  #expect(view.interactionCursor(at: corner) === NSCursor.crosshair)
  view.mouseDown(with: try mouse(.leftMouseDown, at: corner, in: view))
  let resized = CGPoint(x: corner.x + 40, y: corner.y + 30)
  view.mouseDragged(with: try mouse(.leftMouseDragged, at: resized, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: resized, in: view))
  #expect(view.selection == CGRect(x: 400, y: 300, width: 140, height: 130))
  #expect(view.pinned == [first])
}

@Test @MainActor func heldDimensionsCanMoveByTheirLabelAndClose() throws {
  let context = try #require(CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8,
    bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(NSColor.white.cgColor)
  context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
  context.setFillColor(NSColor.black.cgColor)
  context.fill(CGRect(x: 100, y: 100, width: 100, height: 100))
  let image = try #require(context.makeImage())
  let snapshot = ScreenSnapshot(image: image, pixels: try #require(PixelBuffer(image: image)), scaleX: 1, scaleY: 1)
  let view = MeasurementView(frame: CGRect(x: 0, y: 0, width: 400, height: 400), scale: 1,
    snapshot: snapshot, mode: .findDimensions)
  let point = CGPoint(x: 150, y: 250)
  view.mouseDown(with: try mouse(.leftMouseDown, at: point, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: point, in: view))
  let original = try #require(view.heldDimensions)
  let control = try #require(view.labelControls().first { $0.target == .held })
  let start = CGPoint(x: control.label.midX, y: control.label.midY)
  view.mouseDown(with: try mouse(.leftMouseDown, at: start, in: view))
  let end = CGPoint(x: start.x + 10, y: start.y + 20)
  view.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: end, in: view))
  #expect(view.heldDimensions?.rect == original.rect.offsetBy(dx: 10, dy: 20))
  let moved = try #require(view.labelControls().first { $0.target == .held })
  let close = CGPoint(x: moved.close.midX, y: moved.close.midY)
  view.mouseDown(with: try mouse(.leftMouseDown, at: close, in: view))
  view.mouseUp(with: try mouse(.leftMouseUp, at: close, in: view))
  #expect(view.heldDimensions == nil)
  #expect(view.selection == nil)
}

@Test @MainActor func rulerControlPlacementClearsCalipersAndSquareExtensions() throws {
  let screen = try #require(NSScreen.main)
  let name = "Schnaps.ExtendedRulerControls.Tests." + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let state = DesignTools(defaults: defaults)
  state.editing = true
  state.visible = true
  let canvas = DesignCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600), screen: screen, state: state)
  var marker = DesignMarker(tool: .ruler, display: DesignTools.displayID(screen))
  marker.x = 300; marker.y = 250
  marker.calipers = true
  marker.square = true
  for angle in [0.0, 45, 90, 180, 270] {
    marker.angle = angle
    state.markers = [marker]
    let label = try #require(canvas.markerLabelRect(for: marker))
    let close = try #require(canvas.removeButtonRect(for: marker))
    let group = label.union(close)
    #expect(canvas.bounds.contains(group))
    // Check the actual rendered segments, including both calipers and the square.
    let start = CGPoint(x: marker.x, y: marker.y)
    let corner = DesignGeometry.endpoint(origin: start, length: marker.height, degrees: angle + 90)
    let far = DesignGeometry.endpoint(origin: corner, length: marker.width, degrees: angle)
    var segments = [(start, marker.end), (start, corner), (corner, far)]
    for endpoint in [start, marker.end] {
      segments.append((DesignGeometry.endpoint(origin: endpoint, length: 70, degrees: angle + 90),
        DesignGeometry.endpoint(origin: endpoint, length: 70, degrees: angle - 90)))
    }
    for (a, b) in segments {
      for step in 0...100 {
        let point = CGPoint(x: a.x + (b.x - a.x) * Double(step) / 100,
          y: a.y + (b.y - a.y) * Double(step) / 100)
        #expect(!group.insetBy(dx: -3, dy: -3).contains(point))
      }
    }
  }
}
