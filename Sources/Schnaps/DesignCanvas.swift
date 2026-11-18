import AppKit
import CoreText
import MeasurementCore

@MainActor
final class DesignCanvas: NSView {
  let display: NSScreen
  let state: DesignTools
  private let connectedDisplays: () -> [DesignDisplay]
  var snapshot: (() -> ScreenSnapshot?)?
  var inputChanged: (() -> Void)?
  var isDragging: Bool { dragStart != nil }
  var isDraggingMarker: Bool { isDragging && floatingDrag == nil }
  private var floatingDrag: (tool: DesignTool, sample: CGPoint, label: CGRect)?
  private var dragStart: CGPoint?
  private var original: DesignMarker?
  private var originals: [DesignMarker] = []
  private var draggingEnd = false, resizing = false
  private var hoveredID: UUID?
  private let visionCache = VisionPreviewCache()
  private var imageCache: [String: NSImage] = [:]
  private var controlMarkers: [DesignMarker] = []
  private var controlBounds = CGRect.null
  private var controlUnit: String?
  private var controlLabels: [UUID: CGRect] = [:]
  init(frame: CGRect, screen: NSScreen, state: DesignTools,
    connectedDisplays: @escaping () -> [DesignDisplay] = {
      NSScreen.screens.map { (DesignTools.displayID($0), $0.frame) }
    }
  ) {
    display = screen
    self.state = state
    self.connectedDisplays = connectedDisplays
    super.init(frame: frame)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  private var displayID: UInt32 { DesignTools.displayID(display) }
  var displayedMarkers: [DesignMarker] {
    guard state.visible else { return [] }
    let displays = connectedDisplays()
    return state.markers.compactMap { marker in
      guard marker.isVisible else { return nil }
      if marker.display == displayID { return marker }
      guard let source = displays.first(where: { $0.id == marker.display }) else { return nil }
      return marker.projection(on: (displayID, display.frame), from: source.bounds, in: bounds)
    }
  }
  func editableMarker(at point: CGPoint) -> DesignMarker? {
    guard state.editing else { return nil }
    // Controls take priority even when another line crosses them.
    if let marker = displayedMarkers.reversed().first(where: {
      !$0.locked && removeButtonRect(for: $0)?.contains(point) == true
    }) { return marker }
    if let marker = displayedMarkers.reversed().first(where: {
      !$0.locked && markerLabelRects(for: $0).contains(where: { $0.contains(point) })
    }) { return marker }
    return displayedMarkers.reversed().first { !$0.locked && $0.containsEditingPoint(point) }
  }
  func updateHover() {
    let id = bounds.contains(pointer) ? editableMarker(at: pointer)?.id : nil
    if id != hoveredID { hoveredID = id; needsDisplay = true }
  }
  func cursor(at point: CGPoint) -> NSCursor? {
    if isDragging { return .closedHand }
    if floatingHit(at: point) != nil { return .openHand }
    guard state.editing else { return nil }
    guard let marker = editableMarker(at: point) else { return nil }
    if removeButtonRect(for: marker)?.contains(point) == true { return .pointingHand }
    if markerLabelRects(for: marker).contains(where: { $0.contains(point) }) { return .openHand }
    if marker.tool == .ruler
      && hypot(point.x - marker.end.x, point.y - marker.end.y) < 24 {
      return .crosshair
    }
    if marker.tool == .guides { return marker.vertical ? .resizeLeftRight : .resizeUpDown }
    if marker.tool != .ruler && hypot(point.x - marker.rect.maxX, point.y - marker.rect.maxY) < 20 {
      return .crosshair
    }
    return .openHand
  }
  var editingCursor: NSCursor? {
    guard bounds.contains(pointer) || isDragging else { return nil }
    return cursor(at: pointer)
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(rect: .zero,
      options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseMoved], owner: self))
  }
  override func cursorUpdate(with event: NSEvent) {
    (cursor(at: convert(event.locationInWindow, from: nil)) ?? .arrow).set()
  }
  override func mouseMoved(with event: NSEvent) {
    updateHover()
    cursorUpdate(with: event)
  }
  var wantsMouseInput: Bool {
    isDragging || (bounds.contains(pointer)
      && (floatingHit(at: pointer) != nil
        || (state.editing && (state.crosshair || editableMarker(at: pointer) != nil))))
  }
  private var pointer: CGPoint {
    display.frame.displayPoint(from: NSEvent.mouseLocation)
  }
  private func line(_ a: CGPoint, _ b: CGPoint, color: NSColor, width: CGFloat = 1) {
    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = width
    path.move(to: a)
    path.line(to: b)
    path.stroke()
  }
  @MainActor private struct Caption {
    // Caption geometry is queried during event routing, outside AppKit drawing.
    private static let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String):
        NSFont.monospacedSystemFont(ofSize: 11, weight: .medium) as CTFont,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
    ]
    let line: CTLine
    let size: CGSize
    let ascent: CGFloat
    init(_ text: String) {
      line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
      var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
      let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      size = CGSize(width: width, height: ceil(ascent + descent + leading))
      self.ascent = ascent
    }
  }
  private func captionRect(_ text: String, at point: CGPoint) -> CGRect {
    let size = Caption(text).size
    return CGRect(
      x: max(0, min(bounds.maxX - size.width - 12, point.x)),
      y: max(0, min(bounds.maxY - size.height - 8, point.y)),
      width: min(bounds.width, size.width + 10), height: size.height + 6)
  }
  private func drawCaption(_ text: String, in rect: CGRect) {
    NSColor.black.withAlphaComponent(0.86).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let caption = Caption(text)
    context.saveGState()
    context.clip(to: rect)
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: rect.minX + 5, y: rect.minY + 3 + caption.ascent)
    CTLineDraw(caption.line, context)
    context.restoreGState()
  }
  private func markerCaption(_ marker: DesignMarker) -> (String, CGPoint)? {
    if marker.tool != .ruler, marker.display != displayID { return nil }
    if marker.tool == .guides {
      return ("\(marker.vertical ? "x" : "y") \(number(marker.vertical ? marker.x : marker.y)) pt",
        CGPoint(x: marker.vertical ? marker.x + 4 : 8, y: marker.vertical ? 8 : marker.y + 4))
    }
    if marker.tool != .ruler {
      return ("\(number(marker.width)) × \(number(marker.height)) pt · \(number(marker.x)), \(number(marker.y)) · \(number(marker.width/marker.height)):1",
        CGPoint(x: marker.x, y: marker.y - 24))
    }
    guard bounds.contains(CGPoint(x: marker.x, y: marker.y)) else { return nil }
    let pixels = UserDefaults.standard.string(forKey: PreferenceKey.unit) == "px"
    let screen = NSScreen.screens.first { DesignTools.displayID($0) == marker.display } ?? display
    let units = marker.width * (pixels ? screen.backingScaleFactor : 1) / marker.scale
    return ("\(number(units)) \(pixels ? "px" : "pt") · \(number(marker.angle))° · Δ \(number(marker.end.x-marker.x)), \(number(marker.end.y-marker.y))",
      CGPoint(x: marker.x, y: marker.y + 22))
  }
  private func controlFrame(for marker: DesignMarker, avoiding controls: [CGRect]) -> (group: CGRect, label: CGRect)? {
    guard let (text, point) = markerCaption(marker) else { return nil }
    let label = captionRect(text, at: point)
    let closeWidth = label.height + OverlayCloseButton.spacing
    let size = CGSize(width: min(bounds.width, label.width + closeWidth), height: label.height)
    let group: CGRect
    if marker.tool == .ruler || marker.tool == .guides {
      let origin = CGPoint(x: marker.x, y: marker.y)
      let preferred = CGRect(x: label.minX, y: label.midY - size.height / 2,
        width: size.width, height: size.height)
      let gap: CGFloat = marker.tool == .ruler ? (marker.calipers ? 74 : 22) : 8
      group = RulerCaptionPlacement.rect(preferred: preferred, origin: origin,
        angle: marker.tool == .ruler ? marker.angle : marker.vertical ? 90 : 0,
        bounds: bounds, avoiding: controls, gap: gap,
        positiveGap: marker.tool == .ruler && marker.square ? max(gap, marker.height + 4) : gap,
        length: marker.tool == .ruler ? marker.width : nil)
    } else {
      group = OverlayControlPlacement.frame(size: size, around: marker.rect, in: bounds, avoiding: controls)
    }
    return (group, CGRect(x: group.minX, y: group.minY,
      width: max(0, group.width - closeWidth), height: label.height))
  }
  func markerLabelRect(for marker: DesignMarker) -> CGRect? {
    let markers = displayedMarkers
    let unit = UserDefaults.standard.string(forKey: PreferenceKey.unit)
    if controlMarkers != markers || controlBounds != bounds || controlUnit != unit {
      var controls: [CGRect] = []
      controlLabels = [:]
      for marker in markers {
        if let frame = controlFrame(for: marker, avoiding: controls) {
          controlLabels[marker.id] = frame.label
          controls.append(frame.group)
        }
      }
      controlMarkers = markers
      controlBounds = bounds
      controlUnit = unit
    }
    return controlLabels[marker.id] ?? controlFrame(for: marker, avoiding: [])?.label
  }
  private func secondaryCaptions(for marker: DesignMarker) -> [(String, CGRect)] {
    guard marker.display == displayID else { return [] }
    if marker.tool == .screens {
      let top = min(marker.height, marker.topInset)
      let bottom = min(marker.height - top, marker.bottomInset + marker.keyboardHeight)
      let left = min(marker.width, marker.leftInset)
      let right = min(marker.width - left, marker.rightInset)
      let text = "Usable \(number(marker.width-left-right)) × \(number(marker.height-top-bottom)) pt"
      return [(text, captionRect(text, at: CGPoint(x: marker.x + left + 4, y: marker.y + top + 4)))]
    }
    if marker.tool == .guides,
      let next = displayedMarkers.filter({ $0.tool == .guides && $0.vertical == marker.vertical
        && ($0.vertical ? $0.x > marker.x : $0.y > marker.y) }).min(by: {
          (marker.vertical ? $0.x : $0.y) < (marker.vertical ? $1.x : $1.y)
        }) {
      let distance = marker.vertical ? next.x - marker.x : next.y - marker.y
      let text = "\(number(distance)) pt"
      return [(text, captionRect(text, at: CGPoint(
        x: marker.vertical ? (next.x + marker.x) / 2 : 50,
        y: marker.vertical ? 40 : (next.y + marker.y) / 2)))]
    }
    return []
  }
  func markerLabelRects(for marker: DesignMarker) -> [CGRect] {
    [markerLabelRect(for: marker)].compactMap { $0 } + secondaryCaptions(for: marker).map { $0.1 }
  }
  func removeButtonRect(for marker: DesignMarker) -> CGRect? {
    guard state.editing, !marker.locked, let label = markerLabelRect(for: marker) else { return nil }
    return OverlayCloseButton.frame(beside: label)
  }
  private func drawMarkerCaption(_ marker: DesignMarker) {
    guard let (text, _) = markerCaption(marker), let label = markerLabelRect(for: marker) else { return }
    drawCaption(text, in: label)
    guard let button = removeButtonRect(for: marker) else { return }
    OverlayCloseButton.draw(in: button, background: .black.withAlphaComponent(0.86),
      foreground: .white, cornerRadius: 3)
  }
  private func number(_ value: Double) -> String { String(format: "%.1f", value) }
  private func drawImage(_ image: NSImage, in rect: CGRect, opacity: Double = 1) {
    image.draw(
      in: rect, from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.none])
  }
  func clearVisionCache() { visionCache.removeAll() }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill(using: .copy)
    let frame = snapshot?()
    visionCache.prepare(for: frame?.image)
    guard state.isActive else { clearVisionCache(); return }
    if !state.loupe && (!state.visible || (state.vision == .normal && !state.retinaPreview)) {
      clearVisionCache()
    }
    for marker in displayedMarkers { draw(marker, frame: frame) }
    // Draw controls above every tool, matching their priority during hit testing.
    for marker in displayedMarkers {
      for (text, rect) in secondaryCaptions(for: marker) { drawCaption(text, in: rect) }
      drawMarkerCaption(marker)
    }
    let point = pointer
    let crosshair = floatingPoint(.crosshair)
    if state.crosshair, bounds.contains(crosshair) {
      var color = MeasurementPreferences.color(PreferenceKey.guideColor)
      if UserDefaults.standard.bool(forKey: PreferenceKey.autoContrast), let pixel = sample(crosshair) {
        color = pixel.luminance > 0.45 ? .black : .white
      }
      line(
        CGPoint(x: 0, y: crosshair.y), CGPoint(x: bounds.width, y: crosshair.y), color: color,
        width: state.lineWidth)
      line(
        CGPoint(x: crosshair.x, y: 0), CGPoint(x: crosshair.x, y: bounds.height), color: color,
        width: state.lineWidth)
    }
    if state.loupe {
      let frozen =
        state.frozenLoupe.map {
          CGPoint(x: $0.x - display.frame.minX, y: display.frame.maxY - $0.y)
        } ?? point
      if bounds.contains(frozen) { drawLoupe(at: frozen, frame: frame) }
    }
    for tool in [DesignTool.crosshair, .loupe] where floatingEnabled(tool) {
      drawCaption(floatingText(tool), in: floatingLabelRect(tool))
    }
  }
  private func draw(_ marker: DesignMarker, frame: ScreenSnapshot?) {
    let selected = state.editing && (marker.id == state.selectedID || marker.id == hoveredID)
    let color = (NSColor(schnapsHex: marker.color) ?? .systemBlue).withAlphaComponent(
      marker.opacity)
    if marker.tool == .ruler {
      drawRuler(marker, color: color)
      return
    }
    if marker.tool == .guides {
      let a = marker.vertical ? CGPoint(x: marker.x, y: 0) : CGPoint(x: 0, y: marker.y)
      let b =
        marker.vertical
        ? CGPoint(x: marker.x, y: bounds.height) : CGPoint(x: bounds.width, y: marker.y)
      line(a, b, color: color, width: selected ? 2 : 1)
      return
    }
    if let name = marker.imageName, name == URL(fileURLWithPath: name).lastPathComponent {
      if imageCache[name] == nil {
        imageCache[name] = NSImage(contentsOf: DesignTools.imageFolder.appendingPathComponent(name))
      }
      if let image = imageCache[name] { drawImage(image, in: marker.rect, opacity: marker.opacity) }
    }
    if marker.tool == .screens, state.vision != .normal || state.retinaPreview,
      let frame
    {
      let region = marker.rect.intersection(
        CGRect(
          x: 0, y: 0, width: Double(frame.image.width) / frame.scaleX,
          height: Double(frame.image.height) / frame.scaleY))
      if !region.isEmpty, !region.isNull,
        let filtered = visionCache.image(
          source: frame.image,
          crop: CGRect(x: region.minX * frame.scaleX, y: region.minY * frame.scaleY,
                       width: region.width * frame.scaleX, height: region.height * frame.scaleY),
          mode: state.vision, outputSize: state.retinaPreview ? region.size : nil)
      {
        drawImage(NSImage(cgImage: filtered, size: region.size), in: region)
      }
    }
    color.setStroke()
    let border = NSBezierPath(rect: marker.rect)
    border.lineWidth = selected ? 2 : 1
    border.stroke()
    if marker.tool == .overlay || marker.columns > 1 || marker.rows > 1 {
      let column = DesignGeometry.columnWidth(
        width: marker.width, columns: marker.columns, margin: marker.margin, gutter: marker.gutter)
      if column > 0 {
        for index in 0..<marker.columns {
          let rect = CGRect(
            x: marker.x + marker.margin + Double(index) * (column + marker.gutter), y: marker.y,
            width: column, height: marker.height)
          color.withAlphaComponent(marker.opacity * 0.12).setFill()
          NSBezierPath(rect: rect).fill()
          line(rect.origin, CGPoint(x: rect.minX, y: rect.maxY), color: color)
          line(
            CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), color: color)
        }
      }
      for row in 1..<marker.rows {
        let y = marker.y + Double(row) * marker.height / Double(marker.rows)
        line(CGPoint(x: marker.x, y: y), CGPoint(x: marker.x + marker.width, y: y), color: color)
      }
    }
    if marker.spacing >= 2 {
      for y in stride(
        from: marker.y + marker.spacing, to: marker.y + marker.height, by: marker.spacing)
      {
        line(
          CGPoint(x: marker.x, y: y), CGPoint(x: marker.x + marker.width, y: y),
          color: color.withAlphaComponent(marker.opacity * 0.3))
      }
    }
    if marker.marks {
      line(
        CGPoint(x: marker.rect.midX - 8, y: marker.rect.midY),
        CGPoint(x: marker.rect.midX + 8, y: marker.rect.midY), color: color)
      line(
        CGPoint(x: marker.rect.midX, y: marker.rect.midY - 8),
        CGPoint(x: marker.rect.midX, y: marker.rect.midY + 8), color: color)
    }
    if marker.tool == .screens {
      let top = min(marker.height, marker.topInset)
      let bottom = min(marker.height - top, marker.bottomInset + marker.keyboardHeight)
      let left = min(marker.width, marker.leftInset)
      let right = min(marker.width - left, marker.rightInset)
      color.withAlphaComponent(0.16).setFill()
      for rect in [
        CGRect(x: marker.x, y: marker.y, width: marker.width, height: top),
        CGRect(x: marker.x, y: marker.rect.maxY - bottom, width: marker.width, height: bottom),
        CGRect(x: marker.x, y: marker.y + top, width: left, height: marker.height - top - bottom),
        CGRect(
          x: marker.rect.maxX - right, y: marker.y + top, width: right,
          height: marker.height - top - bottom),
      ] { NSBezierPath(rect: rect).fill() }

    }
    if marker.safeAreas {
      for inset in [0.05, 0.1] {
        let safe = marker.rect.insetBy(dx: marker.width * inset, dy: marker.height * inset)
        let path = NSBezierPath(rect: safe)
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.stroke()
      }
    }
    if selected {
      NSColor.controlAccentColor.setFill()
      for p in [marker.rect.origin, CGPoint(x: marker.rect.maxX, y: marker.rect.maxY)] {
        NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
      }
    }
  }
  private func drawRuler(_ marker: DesignMarker, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: marker.x, yBy: marker.y)
    transform.rotate(byDegrees: marker.angle)
    transform.concat()
    color.withAlphaComponent(0.10).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: -18, width: marker.width, height: 36)).fill()
    line(.zero, CGPoint(x: marker.width, y: 0), color: color)
    let pixels = UserDefaults.standard.string(forKey: PreferenceKey.unit) == "px"
    let sourceDisplay = NSScreen.screens.first { DesignTools.displayID($0) == marker.display } ?? display
    let unit = pixels ? sourceDisplay.backingScaleFactor : 1
    let units = marker.width * unit / marker.scale
    let interval = max(1, pow(10, floor(log10(max(1, units / 30)))))
    for value in stride(from: 0.0, through: units, by: interval) {
      let x = value * marker.scale / unit
      let major = Int((value / interval).rounded()) % 5 == 0
      line(CGPoint(x: x, y: major ? -12 : -6), CGPoint(x: x, y: major ? 12 : 6), color: color)
    }
    if marker.marks {
      for fraction in [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.61803398875, 0.75] {
        let x = marker.width * fraction
        line(CGPoint(x: x, y: -18), CGPoint(x: x, y: 18), color: color.withAlphaComponent(0.5))
      }
    }
    if marker.calipers {
      for x in [0.0, marker.width] {
        line(CGPoint(x: x, y: -70), CGPoint(x: x, y: 70), color: color)
      }
    }
    if marker.square {
      line(.zero, CGPoint(x: 0, y: marker.height), color: color)
      line(
        CGPoint(x: 0, y: marker.height), CGPoint(x: marker.width, y: marker.height), color: color)
    }
    NSGraphicsContext.restoreGraphicsState()
    if state.editing && !marker.locked {
      for point in [CGPoint(x: marker.x, y: marker.y), marker.end] {
        let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
        NSColor.white.setFill()
        handle.fill()
        NSColor.controlAccentColor.setStroke()
        handle.lineWidth = 2
        handle.stroke()
      }
    }
  }
  private func sample(_ point: CGPoint) -> InspectorColor? {
    guard let frame = snapshot?() else { return nil }
    let x = floor(point.x * frame.scaleX)
    let y = floor(point.y * frame.scaleY)
    guard x >= 0, y >= 0, x < Double(frame.image.width), y < Double(frame.image.height),
      let pixel = frame.image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
    else { return nil }
    var bytes = [UInt8](repeating: 0, count: 4)
    let success = bytes.withUnsafeMutableBytes { raw in
      guard
        let context = CGContext(
          data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return true
    }
    guard success else { return nil }
    return InspectorColor(
      red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255)
  }
  private func drawLoupe(at point: CGPoint, frame: ScreenSnapshot?) {
    guard let frame else {
      return
    }
    let size = 180.0
    let zoom = max(2, min(32, state.zoom))
    let selection = LoupeSelection(
      point: point, scaleX: frame.scaleX, scaleY: frame.scaleY,
      imageSize: CGSize(width: frame.image.width, height: frame.image.height))
    let sampleRect = selection.sourceRect(size: size, zoom: zoom)
    let cropRect = sampleRect.intersection(
      CGRect(x: 0, y: 0, width: frame.image.width, height: frame.image.height))
    guard let filtered = visionCache.image(source: frame.image, crop: cropRect, mode: state.vision)
    else { return }
    let rect = loupeRect(at: point)
    NSColor.windowBackgroundColor.setFill()
    NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2)).fill()
    let target = CGRect(
      x: rect.midX + (cropRect.minX - selection.pixel.x - 0.5) * zoom,
      y: rect.midY + (cropRect.minY - selection.pixel.y - 0.5) * zoom, width: cropRect.width * zoom,
      height: cropRect.height * zoom)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: rect).addClip()
    drawImage(
      NSImage(cgImage: filtered, size: target.size),
      in: target)
    if state.pixelGrid && zoom >= 6 {
      let step = zoom
      for index in 0...filtered.width {
        let x = target.minX + Double(index) * step
        line(
          CGPoint(x: x, y: target.minY), CGPoint(x: x, y: target.maxY),
          color: .black.withAlphaComponent(0.2))
      }
      for index in 0...filtered.height {
        let y = target.minY + Double(index) * zoom
        line(
          CGPoint(x: target.minX, y: y), CGPoint(x: target.maxX, y: y),
          color: .black.withAlphaComponent(0.2))
      }
    }
    NSGraphicsContext.restoreGraphicsState()
    // Outline the selected pixel without covering its color with centerlines.
    let selectedPixel = CGRect(
      x: rect.midX - zoom / 2, y: rect.midY - zoom / 2, width: zoom, height: zoom)
    NSColor.black.setStroke()
    let outline = NSBezierPath(rect: selectedPixel)
    outline.lineWidth = 3
    outline.stroke()
    NSColor.white.setStroke()
    outline.lineWidth = 1
    outline.stroke()
    if let color = sample(point) {
      let value = color.formatted(state.colorFormat)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.state.colorSample = color
        if self.state.colorValue != value { self.state.colorValue = value }
        self.state.referenceColor = color.formatted(self.state.referenceFormat)
        if let reference = self.state.contrastSample {
          self.state.contrast = String(format: "%.2f:1", color.contrast(with: reference))
        }
      }
    }
  }
  private func floatingEnabled(_ tool: DesignTool) -> Bool {
    (tool == .loupe ? state.loupe : state.crosshair) && bounds.contains(floatingPoint(tool))
  }
  private func floatingPoint(_ tool: DesignTool) -> CGPoint {
    let global = tool == .loupe ? state.frozenLoupe : state.frozenCrosshair
    return global.map { CGPoint(x: $0.x - display.frame.minX, y: display.frame.maxY - $0.y) } ?? pointer
  }
  private func loupeRect(at point: CGPoint) -> CGRect {
    OverlayControlPlacement.clamped(CGRect(x: point.x + 24, y: point.y + 24, width: 180, height: 180),
      in: bounds.insetBy(dx: 8, dy: 8))
  }
  func floatingText(_ tool: DesignTool) -> String {
    if tool == .loupe {
      let zoom = number(max(2, min(32, state.zoom)))
      let color = sample(floatingPoint(tool))?.formatted(state.colorFormat) ?? "Waiting for screen pixels…"
      return "Loupe · \(zoom)× · \(color)"
    }
    let point = floatingPoint(tool)
    let relative = state.relativeOrigin.map {
      CGPoint(x: display.frame.minX + point.x - $0.x, y: $0.y - display.frame.maxY + point.y)
    } ?? point
    return "Crosshair · x \(number(relative.x))  y \(number(relative.y)) pt"
  }
  func floatingLabelRect(_ tool: DesignTool) -> CGRect {
    let text = floatingText(tool)
    let size = Caption(text).size
    let labelSize = CGSize(width: size.width + 10, height: size.height + 6)
    let label = state.floatingLabels[tool]
    let origin = (label?.display == displayID ? label?.origin : nil) ?? CGPoint(
      x: bounds.maxX - labelSize.width - 16,
      y: (tool == .crosshair ? 8 : 42) + (24 - labelSize.height) / 2)
    return OverlayControlPlacement.clamped(CGRect(origin: origin, size: labelSize), in: bounds)
  }
  private func floatingHit(at point: CGPoint) -> DesignTool? {
    for tool in [DesignTool.loupe, .crosshair] where floatingEnabled(tool) {
      if floatingLabelRect(tool).contains(point) { return tool }
    }
    // Keep normal tool use click-through except for the explicit label controls.
    guard state.editing else { return nil }
    // Pointer-following visuals cannot be chased; their stable labels are always grabbable.
    if floatingEnabled(.loupe), state.frozenLoupe != nil, loupeRect(at: floatingPoint(.loupe)).contains(point) {
      return .loupe
    }
    if floatingEnabled(.crosshair), state.frozenCrosshair != nil {
      let anchor = floatingPoint(.crosshair)
      if abs(anchor.x - point.x) < 8 || abs(anchor.y - point.y) < 8 { return .crosshair }
    }
    return nil
  }
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let tool = floatingHit(at: point) {
      floatingDrag = (tool, floatingPoint(tool), floatingLabelRect(tool))
      let global = display.frame.desktopPoint(from: floatingPoint(tool))
      if tool == .loupe { state.frozenLoupe = global } else { state.frozenCrosshair = global }
      window?.makeKey()
      window?.makeFirstResponder(self)
      dragStart = point
      inputChanged?()
      NSCursor.closedHand.set()
      return
    }
    guard let selected = editableMarker(at: point)
    else {
      if state.crosshair {
        state.relativeOrigin = CGPoint(
          x: point.x + display.frame.minX, y: display.frame.maxY - point.y)
      }
      return
    }
    if removeButtonRect(for: selected)?.contains(point) == true {
      state.removeMarker(id: selected.id)
      inputChanged?()
      return
    }
    window?.makeKey()
    window?.makeFirstResponder(self)
    state.beginDragging()
    state.selectedID = selected.id
    if event.modifierFlags.contains(.option) { state.duplicate() }
    guard let saved = state.selected else { state.endDragging(); return }
    let marker = saved.display == displayID ? saved : displayedMarkers.first { $0.id == saved.id } ?? saved
    original = marker
    originals = state.markers
    dragStart = point
    draggingEnd =
      marker.tool == .ruler && !markerLabelRects(for: marker).contains(where: { $0.contains(point) })
      && hypot(point.x - marker.end.x, point.y - marker.end.y) < 24
    resizing =
      marker.tool != .ruler && marker.tool != .guides
      && !markerLabelRects(for: marker).contains(where: { $0.contains(point) })
      && hypot(point.x - marker.rect.maxX, point.y - marker.rect.maxY) < 20
    inputChanged?()
    NSCursor.closedHand.set()
  }
  override func mouseDragged(with event: NSEvent) {
    guard let start = dragStart else { return }
    var point = convert(event.locationInWindow, from: nil)
    let displays = connectedDisplays()
    let desktopPointer = display.frame.desktopPoint(from: point)
    if let drag = floatingDrag {
      let destination = displays.first { $0.bounds.contains(desktopPointer) } ?? (displayID, display.frame)
      let dx = point.x - start.x
      let dy = point.y - start.y
      let sample = display.frame.desktopPoint(from: CGPoint(x: drag.sample.x + dx, y: drag.sample.y + dy))
      let local = destination.bounds.displayPoint(from: sample)
      let size = destination.id == displayID ? bounds.size : destination.bounds.size
      let clipped = CGPoint(x: max(0, min(size.width - 1, local.x)), y: max(0, min(size.height - 1, local.y)))
      let global = destination.bounds.desktopPoint(from: clipped)
      let label = display.frame.desktopPoint(from: CGPoint(x: drag.label.minX + dx, y: drag.label.minY + dy))
      state.floatingLabels[drag.tool] = (destination.id, destination.bounds.displayPoint(from: label))
      if drag.tool == .loupe { state.frozenLoupe = global } else { state.frozenCrosshair = global }
      needsDisplay = true
      return
    }
    guard let marker = original else { return }
    if event.modifierFlags.contains(.control), let frame = snapshot?(),
      let edges = frame.dimensions(
        at: point,
        tolerance: MeasurementPreferences.threshold(MeasurementPreferences.selectedTolerance))
    {
      for x in [edges.horizontal.start.x, edges.horizontal.end.x] where abs(x - point.x) < 10 {
        point.x = x
      }
      for y in [edges.vertical.start.y, edges.vertical.end.y] where abs(y - point.y) < 10 {
        point.y = y
      }
    }
    let dx = point.x - start.x
    let dy = point.y - start.y
    if draggingEnd {
      state.update { item in
        item.width = hypot(point.x - marker.x, point.y - marker.y)
        item.angle = atan2(point.y - marker.y, point.x - marker.x) * 180 / .pi
        if event.modifierFlags.contains(.shift) {
          item.angle = DesignGeometry.snapped(item.angle, step: 45)
        }
      }
    } else if resizing {
      state.update {
        $0.width = point.x - marker.x
        $0.height = point.y - marker.y
      }
    } else {
      state.markers = originals.map { item in
        guard
          item.id == marker.id
            || (state.linked && item.display == marker.display && item.tool == marker.tool
              && !item.locked)
        else { return item }
        var item = item
        item.x += dx
        item.y += dy
        item.validate()
        guard let source = displays.first(where: { $0.id == item.display }) else { return item }
        return item.reanchored(from: source.bounds, on: displays, pointer: desktopPointer)
      }
    }
  }
  func cancelDragging() {
    guard isDragging else { return }
    dragStart = nil
    floatingDrag = nil
    original = nil
    originals = []
    state.endDragging()
  }
  override func mouseUp(with event: NSEvent) {
    guard isDragging else { return }
    cancelDragging()
    inputChanged?()
  }
  private func handleLoupeKey(_ event: NSEvent) -> Bool {
    // Leave application and system shortcuts to their usual handlers.
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
    switch event.keyCode {
    case 123, 124, 125, 126:
      let global = state.frozenLoupe ?? NSEvent.mouseLocation
      // A pinned sample stays on its display even if the pointer moves elsewhere.
      guard display.frame.contains(global), let frame = snapshot?() else { return true }
      let local = CGPoint(x: global.x - display.frame.minX, y: display.frame.maxY - global.y)
      let selection = LoupeSelection(
        point: local, scaleX: frame.scaleX, scaleY: frame.scaleY,
        imageSize: CGSize(width: frame.image.width, height: frame.image.height))
      let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
      let next = selection.moved(
        dx: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,
        dy: event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0)
      state.frozenLoupe = CGPoint(x: next.x + display.frame.minX, y: display.frame.maxY - next.y)
      return true
    default:
      switch event.charactersIgnoringModifiers?.lowercased() {
      case " ":
        if !event.isARepeat {
          state.frozenLoupe = state.frozenLoupe == nil ? NSEvent.mouseLocation : nil
        }
        return true
      case "c":
        let global = state.frozenLoupe ?? NSEvent.mouseLocation
        if let color = sample(CGPoint(x: global.x - display.frame.minX, y: display.frame.maxY - global.y)) {
          state.colorSample = color
          state.colorValue = color.formatted(state.colorFormat)
          if event.modifierFlags.contains(.shift) { state.saveColor() } else { state.copyColor() }
        }
        return true
      default: return false
      }
    }
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      if !event.isARepeat { state.dismiss?() }
      return
    }
    if state.loupe && !state.editing && handleLoupeKey(event) { return }
    guard state.editing else {
      super.keyDown(with: event)
      return
    }
    let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
    switch event.keyCode {
    case 123, 124, 125, 126:
      if event.modifierFlags.contains(.option), state.selected?.tool == .ruler {
        let rotation =
          event.modifierFlags.contains(.control)
          ? 0.1 : event.modifierFlags.contains(.shift) ? 5.0 : 1.0
        state.update {
          $0.angle += (event.keyCode == 123 || event.keyCode == 125) ? -rotation : rotation
        }
      } else {
        state.update { m in
          if !m.locked {
            m.x += event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            m.y += event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0
          }
        }
      }
    case 51, 117: state.remove()
    default:
      switch event.charactersIgnoringModifiers?.lowercased() {
      case " ":
        if state.loupe {
          state.frozenLoupe = state.frozenLoupe == nil ? NSEvent.mouseLocation : nil
        }
      case "o": state.relativeOrigin = NSEvent.mouseLocation
      case "r": state.relativeOrigin = nil
      case "c":
        if state.loupe {
          if event.modifierFlags.contains(.shift) { state.saveColor() } else { state.copyColor() }
        } else {
          state.capture?(true)
        }
      case "p": state.capture?(false)
      case "h", "v", "f":
        let key = event.charactersIgnoringModifiers!.lowercased()
        let list = state.markers.filter {
          $0.display == displayID
            && (key == "f" ? $0.tool == .frames : $0.tool == .guides && $0.vertical == (key == "v"))
        }
        if !list.isEmpty {
          let next =
            (list.firstIndex(where: { $0.id == state.selectedID }).map { $0 + 1 } ?? 0) % list.count
          state.selectedID = list[next].id
        }
      default: super.keyDown(with: event)
      }
    }
  }
}
