import AppKit
import MeasurementCore

@MainActor
final class OverlayController: NSObject {
    private(set) var windows: [OverlayWindow] = []
    private var generation = UUID()
    private var previousApp: NSRunningApplication?
    private var liveTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private let captureScreens: @MainActor () async throws -> [CGDirectDisplayID: ScreenSnapshot]
    private let canCapture: @MainActor () -> Bool
    private var saved: [CGDirectDisplayID: [CGRect]] = [:]
    private var savedDistances: [CGDirectDisplayID: [DimensionSpan]] = [:]
    private var mode: MeasurementMode = .area
    var onActivationChanged: ((Bool) -> Void)?
    var onStateChanged: ((MeasurementMode?) -> Void)?
    var isActive: Bool { !windows.isEmpty }

    init(captureScreens: @escaping @MainActor () async throws -> [CGDirectDisplayID: ScreenSnapshot] = ScreenSnapshot.capture,
         canCapture: @escaping @MainActor () -> Bool = { ScreenRecordingPermission.shared.granted }) {
        self.captureScreens = captureScreens
        self.canCapture = canCapture
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func preferencesChanged() {
        for window in windows { (window.contentView as? MeasurementView)?.synchronizePreferences() }
    }

    func toggle(mode: MeasurementMode = .area) {
        if isActive {
            let sameMode = self.mode == mode
            stop()
            if sameMode { return }
        }
        self.mode = mode
        onActivationChanged?(true)
        onStateChanged?(mode)
        previousApp = NSWorkspace.shared.frontmostApplication
        let token = UUID()
        generation = token
        let freeze = UserDefaults.standard.bool(forKey: PreferenceKey.freezeScreen)
        let initialPointer = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let window = OverlayWindow(screen: screen, freeze: freeze)
            let view = MeasurementView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                       scale: screen.backingScaleFactor, snapshot: nil, mode: mode)
            view.pinned = (saved[id] ?? []).map { $0.intersection(view.bounds) }.filter { !$0.isNull && !$0.isEmpty }
            view.pinnedDistances = savedDistances[id] ?? []
            view.onModeChanged = { [weak self] mode in
                self?.mode = mode
                self?.onStateChanged?(mode)
            }
            view.onClose = { [weak self] in self?.stop() }
            view.onRefresh = { [weak self, weak view] in
                guard let view else { return }
                self?.refresh(mode: view.mode)
            }
            view.onCapture = { [weak self, weak view] region, copy, togglePadding in
                guard let self, let view else { return }
                self.capture(view: view, displayID: id, region: region, copy: copy, togglePadding: togglePadding)
            }
            window.contentView = view
            view.initializePointer(at: initialPointer)
            window.makeFirstResponder(view)
            window.orderFrontRegardless()
            windows.append(window)
        }
        if !freeze { focusWindows(activate: false) }
        // Present the canvas before ScreenCaptureKit enumerates and captures displays.
        // The capture filter excludes our overlays, so they never enter the snapshot.
        captureTask = Task { [weak self] in
            guard let self else { return }
            // Activating or taking key focus can dismiss another app's dropdown.
            // Keep it intact until its frozen image is installed on every display.
            defer {
                if freeze, self.generation == token, !Task.isCancelled {
                    let pointer = NSEvent.mouseLocation
                    for window in self.windows {
                        guard let view = window.contentView as? MeasurementView, view.mode == .findDimensions else { continue }
                        view.initializePointer(at: pointer)
                    }
                    self.focusWindows(activate: true)
                }
            }
            guard self.canCapture() else { return }
            do {
                let snapshots = try await self.captureScreens()
                guard self.generation == token, !Task.isCancelled else { return }
                for window in self.windows {
                    let id = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                    (window.contentView as? MeasurementView)?.updateSnapshot(snapshots[id])
                }
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                NSLog("Schnaps capture: %@", error.localizedDescription)
                for window in self.windows {
                    guard let view = window.contentView as? MeasurementView, view.mode == .findDimensions else { continue }
                    view.reportCaptureFailure()
                }
            }
            guard self.generation == token, !Task.isCancelled else { return }
            self.startLiveCapture(token: token)
        }
    }

    private func focusWindows(activate: Bool) {
        for window in windows {
            window.acceptsMeasurementFocus = true
            window.displayIfNeeded()
        }
        if activate { NSApp.activate(ignoringOtherApps: true) }
        let target = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        target?.makeKeyAndOrderFront(nil)
    }

    func stop() {
        captureTask?.cancel(); captureTask=nil
        liveTask?.cancel(); liveTask=nil
        generation = UUID()
        for window in windows {
            if let id = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
               let view = window.contentView as? MeasurementView {
                view.areaDetection.cancel()
                saved[id] = view.pinned
                savedDistances[id] = view.pinnedDistances
            }
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        onActivationChanged?(false)
        onStateChanged?(nil)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    private func startLiveCapture(token: UUID) {
        guard !UserDefaults.standard.bool(forKey: PreferenceKey.freezeScreen), canCapture() else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, self.generation == token else { return }
                guard !UserDefaults.standard.bool(forKey: PreferenceKey.freezeScreen) else { continue }
                guard self.mode == .findDimensions,
                      self.windows.contains(where: { ($0.contentView as? MeasurementView)?.wantsLiveSnapshot == true }) else { continue }
                do {
                    let frames = try await self.captureScreens()
                    guard self.generation == token else { return }
                    for window in self.windows {
                        let id=(window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                        (window.contentView as? MeasurementView)?.updateSnapshot(frames[id])
                    }
                } catch { /* Keep the last valid frame during a transient capture failure. */ }
            }
        }
    }

    private func capture(view: MeasurementView, displayID: CGDirectDisplayID, region: CGRect, copy: Bool, togglePadding: Bool) {
        let frozen = UserDefaults.standard.bool(forKey: PreferenceKey.freezeScreen) ? view.captureSnapshot : nil
        ScreenRecordingPermission.shared.refresh()
        guard frozen != nil || ScreenRecordingPermission.shared.granted else {
            view.reportScreenshotError(ScreenshotExport.ExportError.noCapture.localizedDescription)
            return
        }
        let token = generation
        Task { [weak self, weak view] in
            guard let self else { return }
            do {
                let image: ScreenSnapshot
                if let frozen { image=frozen }
                else {
                    let frames=try await ScreenSnapshot.capture()
                    guard let frame=frames[displayID] else { throw ScreenshotExport.ExportError.noCapture }; image=frame
                }
                guard self.generation == token else { return }
                self.stop()
                _ = try ScreenshotExport.export(snapshot:image,region:region,copy:copy,togglePadding:togglePadding)
            } catch {
                if let view, self.isActive { view.reportScreenshotError(error.localizedDescription) }
                else { let alert=NSAlert(); alert.messageText=L("Screenshot failed"); alert.informativeText=error.localizedDescription; alert.runModal() }
            }
        }
    }

    private func refresh(mode: MeasurementMode) {
        stop()
        if mode == .findDimensions {
            saved.removeAll()
            savedDistances.removeAll()
        }
        toggle(mode: mode)
    }
}

final class OverlayWindow: NSPanel {
    var acceptsMeasurementFocus: Bool

    init(screen: NSScreen, freeze: Bool) {
        acceptsMeasurementFocus = !freeze
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: true)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Animating a full-display screenshot looks like the desktop itself zooms.
        animationBehavior = .none
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        isRestorable = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { acceptsMeasurementFocus }
    override var canBecomeMain: Bool { acceptsMeasurementFocus }
}

@MainActor
final class MeasurementView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var pinned: [CGRect] = [] { didSet { needsDisplay = true } }
    var pinnedDistances: [DimensionSpan] = [] { didSet { needsDisplay = true } }
    var onClose: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onModeChanged: ((MeasurementMode) -> Void)?
    var onCapture: ((CGRect, Bool, Bool) -> Void)?
    private let scale: CGFloat
    private var snapshot: ScreenSnapshot?
    private var frozenImage: NSImage?
    private var pointerIsInside = false
    private var initialPointer: CGPoint?
    let areaDetection: AreaDetection
    var wantsLiveSnapshot: Bool {
        pointerIsInside && mode == .findDimensions && !dragging && selection == nil && heldDimensions == nil
    }
    var captureSnapshot: ScreenSnapshot? { snapshot }
    private(set) var selection: CGRect?
    private var detectionRegion: CGRect?
    private var toleranceScroll: (movement: CGFloat, unphasedTimestamp: TimeInterval?, distance: CGFloat)?
    private var liveDimensions: Dimensions?
    private(set) var heldDimensions: Dimensions?
    private var modifierFlags: NSEvent.ModifierFlags = []
    private var manualDrag = false
    private var cursor = CGPoint.zero
    private var anchor = CGPoint.zero
    private var original: CGRect?
    private var dragging = false
    private var pressedMouseButton: Int?
    private var controlDrag: (target: ControlTarget, spans: [DimensionSpan], position: CGFloat)?
    private var consumedClick = false
    private static let toleranceLeadingSpacing: CGFloat = 8
    private static let toleranceIconSize: CGFloat = 12
    private static let toleranceIconTextSpacing: CGFloat = 2
    enum ControlTarget: Equatable {
        case selection, area(Int), distances(Int, Int), held, live, guide(Int)

        var showsCloseButton: Bool { self != .live && self != .held }
    }
    struct LabelControl {
        let target: ControlTarget
        let text: String
        let detail: String?
        let label: CGRect
        let close: CGRect?
        let group: CGRect
    }
    private enum DragMode { case create, move, resize(CGPoint) }
    private var dragMode = DragMode.create
    private var unit: MeasurementUnit = .points
    private(set) var mode: MeasurementMode
    private var tolerance: Int
    private var tracking: NSTrackingArea?
    private var message: String?
    private var messageTimer: Timer?
    private var useAlternativeColor = false
    private var messageAlpha: CGFloat = 1
    private var presentation: MeasurementPresentation {
        var value = MeasurementPreferences.presentation
        value.unit = mode == .findDimensions ? .points : unit
        return value
    }
    private var distancePresentation: MeasurementPresentation {
        var value = presentation
        value.unit = .points
        return value
    }
    private var showAlignment = false
    private var guides: [(vertical: Bool, position: CGFloat)] = []

    private var automaticAreaSnapping: Bool {
        mode == .findDimensions && !manualDrag && modifierFlags.intersection([.option, .shift]).isEmpty
    }
    private var isCreatingFindDimensionsArea: Bool {
        guard mode == .findDimensions, dragging, case .create = dragMode else { return false }
        return true
    }
    var showsSnapIndicator: Bool {
        guard mode == .findDimensions, selection != nil else { return false }
        if detectionRegion != nil { return true }
        guard dragging, case .create = dragMode else { return false }
        return automaticAreaSnapping
    }

    init(frame: CGRect, scale: CGFloat, snapshot: ScreenSnapshot?, mode: MeasurementMode,
         areaDetection: AreaDetection = AreaDetection()) {
        self.scale = scale
        self.snapshot = snapshot
        self.frozenImage = snapshot.map { NSImage(cgImage: $0.image, size: frame.size) }
        self.areaDetection = areaDetection
        self.mode = mode
        self.unit = MeasurementUnit(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.unit) ?? "pt") ?? .points
        self.tolerance = MeasurementPreferences.tolerance
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("measurement-overlay")
        setAccessibilityLabel("Measurement canvas")
        setAccessibilityHelp("Drag to measure. S switches tools, U switches units in Measure Area, Scroll up/down or T/Shift-T changes tolerance, C copies a screenshot, P saves, Enter copies dimensions, Escape exits.")
        appearance = MeasurementPreferences.appearance
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func resetCursorRects() {
        let hidden=NSCursor(image:NSImage(size:NSSize(width:16,height:16),flipped:false) { _ in true },hotSpot:.zero)
        addCursorRect(bounds,cursor:UserDefaults.standard.bool(forKey:PreferenceKey.showCursor) ? .crosshair : hidden)
        for control in labelControls() {
            addCursorRect(control.label, cursor: .openHand)
            if let close = control.close { addCursorRect(close, cursor: .pointingHand) }
        }
    }
    func updateSnapshot(_ value: ScreenSnapshot?) {
        // Always accept the first frame, even if a drag began during capture.
        guard snapshot == nil || (!dragging && heldDimensions == nil && selection == nil) else { return }
        snapshot=value
        frozenImage = value.map { NSImage(cgImage: $0.image, size: bounds.size) }
        if detectionRegion != nil { detectSelectedArea() }
        updateLiveDimensions(); needsDisplay=true
    }
    private func detectSelectedArea() {
        guard let snapshot, let region = detectionRegion else { return }
        areaDetection.request(snapshot: snapshot, region: region, tolerance: tolerance) { [weak self] detected in
            guard let self else { return }
            self.selection = detected ?? region
            self.needsDisplay = true
        }
    }

    func reportScreenshotError(_ text: String) { flash(text) }
    private func dimensions(at point: CGPoint) -> Dimensions? {
        guard let found=snapshot?.dimensions(at:point,tolerance:tolerance) else { return nil }
        let d=UserDefaults.standard
        return MeasurementSnapping.apply(found,at:point,
            verticalGuides:d.bool(forKey:PreferenceKey.snapGuides) ? guides.filter(\.vertical).map(\.position) : [],
            horizontalGuides:d.bool(forKey:PreferenceKey.snapGuides) ? guides.filter { !$0.vertical }.map(\.position) : [],
            rectangles:d.bool(forKey:PreferenceKey.snapObjects) ? pinned : [])
    }
    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        // Opening or focusing the panel can send an enter event without pointer movement.
        updatePointer(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) {
        pointerIsInside = false
        liveDimensions = nil
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let initialPointer, hypot(point.x - initialPointer.x, point.y - initialPointer.y) >= 1 / scale {
            self.initialPointer = nil
        }
        updatePointer(at: point)
    }

    private func updatePointer(at point: CGPoint) {
        pointerIsInside = true
        cursor = point
        if let interaction = interactionCursor(at: cursor) { interaction.set() }
        else if UserDefaults.standard.bool(forKey: PreferenceKey.showCursor) { NSCursor.crosshair.set() }
        else { NSCursor(image: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }, hotSpot: .zero).set() }
        // A held measurement does not change when the pointer moves. Redraw only
        // if its alignment guides follow the pointer.
        if selection != nil || heldDimensions != nil {
            if showAlignment { needsDisplay = true }
            return
        }
        updateLiveDimensions()
        needsDisplay = true
    }

    func initializePointer(at screenPoint: CGPoint) {
        guard let window, pressedMouseButton == nil else { return }
        pointerIsInside = window.frame.contains(screenPoint)
        cursor = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        // Every panel can receive tracking events as the overlay takes focus.
        if mode == .findDimensions {
            initialPointer = cursor
            liveDimensions = nil
            needsDisplay = true
        }
    }

    private func updateLiveDimensions() {
        if pointerIsInside, initialPointer == nil, selection == nil, heldDimensions == nil, mode == .findDimensions {
            liveDimensions = dimensions(at: cursor)
        } else { liveDimensions = nil }
    }

    private func rounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (min(max(point.x, 0), bounds.width) * scale).rounded() / scale,
                y: (min(max(point.y, 0), bounds.height) * scale).rounded() / scale)
    }

    override func mouseDown(with event: NSEvent) {
        pressedMouseButton = event.buttonNumber
        initialPointer = nil
        areaDetection.cancel()
        pointerIsInside = true
        window?.makeFirstResponder(self)
        modifierFlags = event.modifierFlags
        anchor = rounded(convert(event.locationInWindow, from: nil))
        cursor = anchor
        dragging = false
        manualDrag = event.type == .rightMouseDown
        original = selection
        detectionRegion = nil
        controlDrag = nil
        consumedClick = false
        let controls = labelControls()
        if let control = controls.reversed().first(where: { $0.close?.contains(anchor) == true }) {
            removeControl(control.target)
            consumedClick = true
            needsDisplay = true
            return
        }
        if let control = controls.reversed().first(where: { $0.label.contains(anchor) }) {
            beginControlDrag(control.target)
            return
        }
        if let target = lineTarget(at: anchor) {
            beginControlDrag(target)
            return
        }
        if let selection {
            let corners = [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
                           CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)]
            if let corner = corners.first(where: { hypot($0.x - anchor.x, $0.y - anchor.y) < 9 }) {
                let opposite = CGPoint(x: corner.x == selection.minX ? selection.maxX : selection.minX,
                                       y: corner.y == selection.minY ? selection.maxY : selection.minY)
                dragMode = .resize(opposite)
                return
            }
            if selection.contains(anchor) { dragMode = .move; return }
        }
        // Clicking a pin restores it for editing.
        if let index = pinned.lastIndex(where: { $0.contains(anchor) }) {
            beginControlDrag(.area(index))
            return
        }
        dragMode = .create
        heldDimensions = nil
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedMouseButton == event.buttonNumber, !consumedClick else { return }
        modifierFlags = event.modifierFlags
        let point = rounded(convert(event.locationInWindow, from: nil))
        guard dragging || hypot(point.x - anchor.x, point.y - anchor.y) >= 2 else { return }
        dragging = true
        cursor = point
        NSCursor.closedHand.set()
        if let drag = controlDrag {
            let dx = point.x - anchor.x, dy = point.y - anchor.y
            if case .guide(let index) = drag.target {
                guides[index].position = drag.position + (guides[index].vertical ? dx : dy)
            } else {
                let minX = drag.spans.map { min($0.start.x, $0.end.x) }.min() ?? 0
                let maxX = drag.spans.map { max($0.start.x, $0.end.x) }.max() ?? 0
                let minY = drag.spans.map { min($0.start.y, $0.end.y) }.min() ?? 0
                let maxY = drag.spans.map { max($0.start.y, $0.end.y) }.max() ?? 0
                let x = max(-minX, min(bounds.maxX - maxX, dx))
                let y = max(-minY, min(bounds.maxY - maxY, dy))
                let spans = drag.spans.map { DimensionSpan(
                    start: CGPoint(x: $0.start.x + x, y: $0.start.y + y),
                    end: CGPoint(x: $0.end.x + x, y: $0.end.y + y)) }
                switch drag.target {
                case .distances(let index, let count): pinnedDistances.replaceSubrange(index..<index+count, with: spans)
                case .held: heldDimensions = Dimensions(horizontal: spans[0], vertical: spans[1])
                default: break
                }
            }
            liveDimensions = nil
            needsDisplay = true
            return
        }
        switch dragMode {
        case .create:
            selection = MeasurementGeometry.rectangle(from: anchor, to: point, within: bounds,
                                                       square: event.modifierFlags.contains(.shift))
        case .resize(let opposite):
            selection = MeasurementGeometry.rectangle(from: opposite, to: point, within: bounds,
                                                       square: event.modifierFlags.contains(.shift))
        case .move:
            if let original {
                selection = MeasurementGeometry.translated(original, dx: point.x - anchor.x, dy: point.y - anchor.y, within: bounds)
            }
        }
        liveDimensions = nil
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        // The overlay can appear in the middle of a click started in another window.
        guard pressedMouseButton == event.buttonNumber else { return }
        pressedMouseButton = nil
        if consumedClick || controlDrag != nil {
            consumedClick = false
            controlDrag = nil
            dragging = false
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            return
        }
        modifierFlags = event.modifierFlags
        if case .create = dragMode {
            if !dragging {
                heldDimensions = mode == .findDimensions ? dimensions(at: anchor) : nil
                liveDimensions = nil
            } else if automaticAreaSnapping, let rect = selection {
                detectionRegion = rect
                detectSelectedArea()
            }
        }
        if let rect = selection, rect.width < 1 / scale || rect.height < 1 / scale { selection = nil }
        dragging = false
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) {
        pressedMouseButton = event.buttonNumber
        initialPointer = nil
        controlDrag = nil
        consumedClick = false
        areaDetection.cancel()
        pointerIsInside = true
        window?.makeFirstResponder(self)
        modifierFlags = event.modifierFlags
        anchor = rounded(convert(event.locationInWindow, from: nil))
        cursor = anchor
        dragging = false
        manualDrag = true
        detectionRegion = nil
        original = nil
        dragMode = .create
        selection = nil
        heldDimensions = nil
        liveDimensions = nil
    }
    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) {
        guard pressedMouseButton == event.buttonNumber else { return }
        if dragging { mouseUp(with: event) }
        else {
            pressedMouseButton = nil
            selection = nil; heldDimensions = nil; mouseMoved(with: event)
        }
    }
    override func flagsChanged(with event: NSEvent) {
        modifierFlags = event.modifierFlags
        showAlignment = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let character = event.charactersIgnoringModifiers?.lowercased()
        let usesMeasuredArea = [UInt16(36), 76, 49].contains(event.keyCode) || ["c", "p"].contains(character ?? "")
        if areaDetection.isPending && usesMeasuredArea {
            let completion = areaDetection.completionForCurrent()
            Task { [weak self] in
                guard await completion.value else { return }
                self?.keyDown(with: event)
            }
            return
        }
        let shift = event.modifierFlags.contains(.shift)
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: areaDetection.cancel(); onClose?()
        case 36, 76: copyDimensions(css: shift)
        case 49: pin()
        case 51, 117:
            areaDetection.cancel()
            if selection != nil { selection = nil; detectionRegion = nil }
            else if heldDimensions != nil { heldDimensions = nil }
            else if !pinnedDistances.isEmpty { pinnedDistances.removeLast() }
            else if !pinned.isEmpty { pinned.removeLast() }
            updateLiveDimensions()
        case 123, 124, 125, 126:
            areaDetection.cancel()
            guard let rect = selection else { return }
            detectionRegion = nil
            let step: CGFloat = (shift ? 10 : 1) / (presentation.unit == .pixels ? scale : 1)
            let dx: CGFloat = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy: CGFloat = event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0
            if event.modifierFlags.contains(.option) {
                selection = CGRect(x: rect.minX, y: rect.minY,
                                   width: min(max(1 / scale, rect.width + dx), bounds.maxX - rect.minX),
                                   height: min(max(1 / scale, rect.height + dy), bounds.maxY - rect.minY))
            } else { selection = MeasurementGeometry.translated(rect, dx: dx, dy: dy, within: bounds) }
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "u": toggleUnit()
            case "s": toggleMode()
            case "r": refresh()
            case "t": cycleTolerance(backward: shift)
            case "c" where command: copyDimensions(css: shift)
            case "c": captureScreenshot(copy: true, togglePadding: event.modifierFlags.contains(.option))
            case "p": captureScreenshot(copy: false, togglePadding: event.modifierFlags.contains(.option))
            case "x": useAlternativeColor.toggle()
            case "k" where command: clear()
            case "z" where command:
                if !pinned.isEmpty {
                    areaDetection.cancel()
                    selection = pinned.removeLast(); detectionRegion = nil
                }
            case "h":
                if shift { guides.append((false, cursor.y)) }
                else { pinDistance(horizontal: true) }
            case "v":
                if shift { guides.append((true, cursor.x)) }
                else { pinDistance(horizontal: false) }
            default: break
            }
        }
        updateLiveDimensions()
        needsDisplay = true
    }

    private func toggleUnit() {
        guard mode == .area else {
            flash("Screen points")
            return
        }
        unit = unit == .points ? .pixels : .points
        UserDefaults.standard.set(unit.rawValue, forKey: PreferenceKey.unit)
        flash(unit == .points ? "Screen points" : "Display pixels")
    }
    private func toggleMode() {
        areaDetection.cancel()
        detectionRegion = nil
        toleranceScroll = nil
        mode = mode == .area ? .findDimensions : .area
        onModeChanged?(mode)
        liveDimensions = nil
        heldDimensions = nil
        updateLiveDimensions()
        if mode == .findDimensions && snapshot == nil { reportCaptureFailure() }
        else { flash(mode.rawValue) }
    }

    func reportCaptureFailure() {
        flash("Capture unavailable. R to retry, S to measure an area.")
    }

    private func cycleTolerance(backward: Bool) {
        let preset=MeasurementPreferences.selectedTolerance.cycled(backward:backward)
        MeasurementPreferences.selectTolerance(preset)
        synchronizePreferences()
        if mode != .findDimensions { flash(toleranceTitle) }
    }

    func synchronizeTolerance() { synchronizePreferences() }
    func synchronizePreferences() {
        let previousTolerance = tolerance
        tolerance=MeasurementPreferences.tolerance
        unit=MeasurementPreferences.presentation.unit
        appearance=MeasurementPreferences.appearance
        window?.invalidateCursorRects(for:self)
        if mode == .findDimensions {
            if let held = heldDimensions {
                // Label dragging changes the drag anchor; remeasure at the held axes instead.
                heldDimensions = dimensions(at: CGPoint(x: held.vertical.start.x, y: held.horizontal.start.y))
            }
            if previousTolerance != tolerance, detectionRegion != nil { detectSelectedArea() }
        }
        updateLiveDimensions(); needsDisplay=true
    }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        guard mode == .findDimensions, snapshot != nil, !dragging,
              let distance = MeasurementPreferences.toleranceScrollSensitivity.scrollDistance(precise: precise) else {
            toleranceScroll = nil
            return
        }
        guard event.momentumPhase.isEmpty else { return }
        let phase = event.phase
        if precise, !phase.isEmpty, phase != .changed {
            toleranceScroll = nil
        }
        guard phase != .ended, phase != .cancelled, phase != .mayBegin else { return }

        let delta = event.scrollingDeltaY
        guard abs(delta) > abs(event.scrollingDeltaX) else { return }
        // A discrete wheel event counts once even if macOS accelerates its delta.
        let unphasedTimestamp = precise && phase.isEmpty ? event.timestamp : nil
        var movement = precise ? delta : (delta < 0 ? -1 : 1)
        if let previous = toleranceScroll, previous.distance == distance,
           (previous.unphasedTimestamp == nil) == (unphasedTimestamp == nil),
           event.timestamp - (previous.unphasedTimestamp ?? event.timestamp) <= 0.4,
           precise || previous.movement.sign == movement.sign {
            movement += previous.movement
        }
        guard abs(movement) >= distance else {
            toleranceScroll = (movement, unphasedTimestamp, distance)
            return
        }
        toleranceScroll = nil
        // One event advances at most one preset.
        let current = MeasurementPreferences.selectedTolerance
        let preset = current.stepped(by: movement < 0 ? -1 : 1)
        guard preset != current else { return }
        MeasurementPreferences.selectTolerance(preset)
        synchronizePreferences()
    }

    private func pin() {
        if let rect = selection, rect.width > 0, rect.height > 0 {
            pinned.append(rect)
            detectionRegion = nil
            selection = nil
        } else if let dimensions = heldDimensions ?? liveDimensions {
            pinnedDistances.append(contentsOf: [dimensions.horizontal, dimensions.vertical])
            heldDimensions = nil
        } else { return }
        updateLiveDimensions()
        flash("Measurement pinned")
    }
    private func pinDistance(horizontal: Bool) {
        guard let dimensions = heldDimensions ?? liveDimensions else { return }
        pinnedDistances.append(horizontal ? dimensions.horizontal : dimensions.vertical)
        flash(horizontal ? "Horizontal distance pinned" : "Vertical distance pinned")
    }
    private func clear() {
        areaDetection.cancel()
        pinned.removeAll(); pinnedDistances.removeAll(); guides.removeAll()
        detectionRegion = nil
        selection = nil; heldDimensions = nil
        updateLiveDimensions()
        flash("Measurements cleared")
    }
    private func refresh() { onRefresh?() }

    private func copyDimensions(css: Bool) {
        guard let rect = selection ?? (heldDimensions ?? liveDimensions)?.rect ?? pinned.last else {
            if let distance = pinnedDistances.last {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(distancePresentation.distance(distance.length, scale: scale), forType: .string)
                flash("Distance copied")
            } else { flash("Move the pointer or drag a region first") }
            return
        }
        let value = presentation.clipboard(rect, scale: scale, forceCSS: css)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        flash("Copied  \(value)")
    }
    private func captureScreenshot(copy: Bool, togglePadding: Bool) {
        guard let region=selection ?? (heldDimensions ?? liveDimensions)?.rect ?? pinned.last,
              region.width > 0, region.height > 0 else {
            flash(L("Select an area or point between edges first.")); return
        }
        onCapture?(region,copy,togglePadding)
    }
    private func flash(_ text: String) {
        messageTimer?.invalidate(); message=L(text); messageAlpha=1; needsDisplay=true
        let animated=UserDefaults.standard.bool(forKey:PreferenceKey.animations) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start=Date()
        messageTimer=Timer.scheduledTimer(withTimeInterval:animated ? 0.05 : 2,repeats:animated) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed=Date().timeIntervalSince(start)
            if elapsed >= 2 || !animated { timer.invalidate() }
            MainActor.assumeIsolated {
                if elapsed >= 2 || !animated { self.message=nil }
                else { self.messageAlpha=CGFloat(min(1,elapsed/0.12)*min(1,max(0,(2-elapsed)/0.3))) }
                self.needsDisplay=true
            }
        }
    }
    // Keep the selected color across the measurement. Auto contrast adds an outline.
    var measurementColor: NSColor {
        MeasurementPreferences.color(useAlternativeColor ? PreferenceKey.alternativeColor : PreferenceKey.overlayColor)
    }
    private func aspectRatio(_ rect: CGRect, distance: Bool) -> String? {
        let d=UserDefaults.standard
        guard d.bool(forKey:distance ? PreferenceKey.aspectDistance : PreferenceKey.aspectArea) else { return nil }
        return (AspectRatioStyle(rawValue:d.string(forKey:PreferenceKey.aspectStyle) ?? "") ?? .commonOnly).label(width:rect.width,height:rect.height)
    }

    private func findDimensionsLabelText(_ rect: CGRect) -> String {
        FindDimensionsLabel.text(for: rect, rounded: presentation.roundedPoints)
            + (aspectRatio(rect, distance: true).map { "  " + $0 } ?? "")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let description = selection.map { areaLabelText($0) } ?? (heldDimensions ?? liveDimensions).map {
            findDimensionsLabelText($0.rect)
        }
        var accessibility = description.map { $0 + (showsSnapIndicator ? ", " + L("Snap") : "") } ?? "No active measurement"
        if selection == nil, heldDimensions == nil, liveDimensions != nil {
            accessibility += ", " + toleranceTitle
        }
        setAccessibilityValue(accessibility)
        // Erase previous marks even when the frozen frame has translucent pixels.
        // Keep the canvas hit-testable before and after capture.
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill(using: .copy)
        if let frozenImage, UserDefaults.standard.bool(forKey: PreferenceKey.freezeScreen) {
            frozenImage.draw(in: bounds, from: .zero,
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        for guide in guides {
            line(from: guide.vertical ? CGPoint(x: guide.position, y: 0) : CGPoint(x: 0, y: guide.position),
                 to: guide.vertical ? CGPoint(x: guide.position, y: bounds.height) : CGPoint(x: bounds.width, y: guide.position),
                 color: MeasurementPreferences.color(PreferenceKey.guideColor), dashed: true)
        }
        if showAlignment && pointerIsInside && initialPointer == nil {
            let color = measurementColor.withAlphaComponent(0.6)
            line(from: CGPoint(x: cursor.x, y: 0), to: CGPoint(x: cursor.x, y: bounds.height), color: color, dashed: true)
            line(from: CGPoint(x: 0, y: cursor.y), to: CGPoint(x: bounds.width, y: cursor.y), color: color, dashed: true)
        }
        for (index, rect) in pinned.enumerated() { drawMeasurement(rect, index: index + 1, active: false) }
        if let rect = selection { drawMeasurement(rect, index: nil, active: true) }
        for distance in pinnedDistances { drawDistance(distance, held: true) }
        if let dimensions = heldDimensions ?? liveDimensions {
            drawDistance(dimensions.horizontal, held: heldDimensions != nil)
            drawDistance(dimensions.vertical, held: heldDimensions != nil)
        }
        for control in labelControls() {
            drawPill(control.text, in: control.label, detail: control.detail)
            if let close = control.close {
                OverlayCloseButton.draw(in: close)
            }
            if control.target == .selection && showsSnapIndicator {
                drawSnapIcon(in: CGRect(x: control.label.midX - 8, y: control.label.maxY + 4, width: 16, height: 16))
            }
        }
        if let message {
            NSGraphicsContext.saveGraphicsState()
            if let context=NSGraphicsContext.current?.cgContext { context.setAlpha(messageAlpha) }
            let size = CGSize(width: labelWidth(message), height: OverlayLabelStyle.height)
            let frame = CGRect(x: bounds.midX - size.width / 2, y: bounds.maxY - 46,
                width: size.width, height: size.height)
            drawPill(message, in: OverlayControlPlacement.clamped(frame, in: bounds.insetBy(dx: 8, dy: 8)))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private var toleranceTitle: String {
        L("Tolerance") + ": " + L(MeasurementPreferences.selectedTolerance.title) + " (\(tolerance))"
    }
    private func toleranceDetail(for target: ControlTarget) -> String? {
        guard target == .live else { return nil }
        let preset = MeasurementPreferences.selectedTolerance
        return L(preset == .medium ? "Med" : preset.title)
    }
    private var detailAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: OverlayLabelStyle.secondaryForeground]
    }

    private func toleranceBadgeWidth(_ text: String) -> CGFloat {
        Self.toleranceLeadingSpacing + Self.toleranceIconSize + Self.toleranceIconTextSpacing
            + (text as NSString).size(withAttributes: detailAttributes).width
    }

    func labelControls() -> [LabelControl] {
        var controls: [LabelControl] = []
        let labelHeight = OverlayLabelStyle.height
        let closeWidth = labelHeight + OverlayCloseButton.spacing
        func append(_ target: ControlTarget, text: String, group: CGRect) {
            let detail = toleranceDetail(for: target)
            let reservedWidth = target.showsCloseButton ? closeWidth : 0
            let label = CGRect(x: group.minX, y: group.minY,
                width: max(0, group.width - reservedWidth), height: labelHeight)
            let close = target.showsCloseButton ? OverlayCloseButton.frame(beside: label) : nil
            controls.append(LabelControl(target: target, text: text, detail: detail, label: label, close: close, group: group))
        }
        func size(_ text: String, target: ControlTarget, extraHeight: CGFloat = 0) -> CGSize {
            let detail = toleranceDetail(for: target)
            let badgeWidth = detail.map { toleranceBadgeWidth($0) } ?? 0
            return CGSize(width: labelWidth(text) + badgeWidth + (target.showsCloseButton ? closeWidth : 0),
                height: labelHeight + extraHeight)
        }
        func area(_ rect: CGRect, target: ControlTarget, prefix: String = "") {
            let text = prefix + areaLabelText(rect)
            let group = AreaMeasurementLabel.frame(for: rect,
                size: size(text, target: target, extraHeight: target == .selection && showsSnapIndicator ? 20 : 0),
                in: bounds, avoiding: controls.map(\.group))
            append(target, text: text, group: group)
        }
        for (index, rect) in pinned.enumerated() { area(rect, target: .area(index), prefix: "\(index + 1)  ·  ") }
        if let selection, !isCreatingFindDimensionsArea { area(selection, target: .selection) }
        func dimensions(_ value: Dimensions, target: ControlTarget) {
            let text = findDimensionsLabelText(value.rect)
            let center = CGPoint(x: value.vertical.start.x, y: value.horizontal.start.y)
            let group = FindDimensionsLabel.frame(at: center, size: size(text, target: target), in: bounds,
                avoiding: controls.map(\.group))
            append(target, text: text, group: group)
        }
        var index = 0
        while index < pinnedDistances.count {
            let span = pinnedDistances[index]
            if index + 1 < pinnedDistances.count, let pair = FindDimensionsLabel.pair(span, pinnedDistances[index + 1]) {
                dimensions(pair, target: .distances(index, 2))
                index += 2
            } else {
                let text = distancePresentation.distance(span.length, scale: scale, horizontal: span.isHorizontal)
                let target = ControlTarget.distances(index, 1)
                append(target, text: text, group: DimensionLabelPlacement.frame(for: span,
                    size: size(text, target: target), in: bounds, avoiding: controls.map(\.group)))
                index += 1
            }
        }
        if let value = heldDimensions ?? liveDimensions { dimensions(value, target: heldDimensions == nil ? .live : .held) }
        for (index, guide) in guides.enumerated() {
            let target = ControlTarget.guide(index)
            let text = "\(guide.vertical ? "x" : "y") \(presentation.value(guide.position, scale: scale))"
            let preferred = CGRect(x: guide.vertical ? guide.position + 10 : 8,
                y: guide.vertical ? 8 : guide.position + 10, width: size(text, target: target).width, height: labelHeight)
            let group = RulerCaptionPlacement.rect(preferred: preferred,
                origin: guide.vertical ? CGPoint(x: guide.position, y: 0) : CGPoint(x: 0, y: guide.position),
                angle: guide.vertical ? 90 : 0, bounds: bounds.insetBy(dx: 8, dy: 8),
                avoiding: controls.map(\.group), gap: 8)
            append(target, text: text, group: group)
        }
        return controls
    }

    func interactionCursor(at point: CGPoint) -> NSCursor? {
        if dragging { return .closedHand }
        let controls = labelControls()
        if controls.contains(where: { $0.close?.contains(point) == true }) { return .pointingHand }
        if controls.contains(where: { $0.label.contains(point) }) { return .openHand }
        if let selection, selection.insetBy(dx: -8, dy: -8).contains(point) {
            let corners = [selection.origin, CGPoint(x: selection.maxX, y: selection.minY),
                CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)]
            if corners.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 9 }) { return .crosshair }
            return .openHand
        }
        return pinned.contains(where: { $0.contains(point) }) || lineTarget(at: point) != nil ? .openHand : nil
    }

    private func lineTarget(at point: CGPoint) -> ControlTarget? {
        for control in labelControls().reversed() {
            switch control.target {
            case .distances(let index, let count):
                if pinnedDistances[index..<index+count].contains(where: {
                    DesignGeometry.distance(point, toSegmentFrom: $0.start, to: $0.end) < 8
                }) { return control.target }
            case .held:
                if let heldDimensions, [heldDimensions.horizontal, heldDimensions.vertical].contains(where: {
                    DesignGeometry.distance(point, toSegmentFrom: $0.start, to: $0.end) < 8
                }) { return .held }
            case .guide(let index):
                let guide = guides[index]
                if abs(guide.position - (guide.vertical ? point.x : point.y)) < 8 { return control.target }
            default: break
            }
        }
        return nil
    }

    private func beginControlDrag(_ target: ControlTarget) {
        dragMode = .move
        switch target {
        case .selection: original = selection
        case .area(let index):
            // Keep an existing active selection by pinning it before restoring another one.
            let restored = pinned.remove(at: index)
            if let selection { pinned.append(selection) }
            selection = restored
            original = restored
        case .distances(let index, let count):
            controlDrag = (target, Array(pinnedDistances[index..<index+count]), 0)
        case .held, .live:
            if let value = heldDimensions ?? liveDimensions {
                heldDimensions = value
                liveDimensions = nil
                controlDrag = (.held, [value.horizontal, value.vertical], 0)
            }
        case .guide(let index): controlDrag = (target, [], guides[index].position)
        }
        NSCursor.closedHand.set()
        needsDisplay = true
    }

    private func removeControl(_ target: ControlTarget) {
        switch target {
        case .selection: selection = nil; detectionRegion = nil
        case .area(let index): pinned.remove(at: index)
        case .distances(let index, let count): pinnedDistances.removeSubrange(index..<index+count)
        case .held, .live: heldDimensions = nil; liveDimensions = nil
        case .guide(let index): guides.remove(at: index)
        }
        window?.invalidateCursorRects(for: self)
    }

    private func drawMeasurement(_ rect: CGRect, index: Int?, active: Bool) {
        let color = index == nil ? measurementColor : MeasurementPreferences.color(PreferenceKey.guideColor)
        color.withAlphaComponent(active ? 0.09 : 0.045).setFill()
        rect.fill()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1 / scale
        if index != nil { path.setLineDash([4, 3], count: 2, phase: 0) }
        if active && UserDefaults.standard.bool(forKey: PreferenceKey.autoContrast) {
            let halo = color.relativeLuminance > 0.45 ? NSColor.black : NSColor.white
            halo.withAlphaComponent(0.65).setStroke()
            path.lineWidth = 3 / scale
            path.stroke()
            path.lineWidth = 1 / scale
        }
        color.setStroke()
        path.stroke()
        if active {
            for point in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                          CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
                NSColor.black.setFill()
                let handle = NSBezierPath(roundedRect: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6), xRadius: 1, yRadius: 1)
                handle.fill(); color.setStroke(); handle.stroke()
            }
        }
    }

    private func areaLabelText(_ rect: CGRect) -> String {
        presentation.label(rect, scale: scale) + (aspectRatio(rect, distance: false).map { " · " + $0 } ?? "")
    }

    /// A small horseshoe magnet denotes automatic edge snapping, without a text capsule.
    private func drawSnapIcon(in rect: CGRect) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX + 3, y: rect.minY + 2))
        path.line(to: CGPoint(x: rect.minX + 3, y: rect.minY + 8))
        path.curve(to: CGPoint(x: rect.minX + 13, y: rect.minY + 8),
                   controlPoint1: CGPoint(x: rect.minX + 3, y: rect.minY + 15),
                   controlPoint2: CGPoint(x: rect.minX + 13, y: rect.minY + 15))
        path.line(to: CGPoint(x: rect.minX + 13, y: rect.minY + 2))
        path.lineWidth = 3
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 5
        path.stroke()
        NSColor.labelColor.setStroke()
        path.lineWidth = 3
        path.stroke()
        NSColor.windowBackgroundColor.setFill()
        CGRect(x: rect.minX + 1, y: rect.minY + 5, width: 4, height: 1).fill()
        CGRect(x: rect.minX + 11, y: rect.minY + 5, width: 4, height: 1).fill()
    }

    private func drawDistance(_ distance: DimensionSpan, held: Bool) {
        let color = measurementColor
        line(from: distance.start, to: distance.end, color: color, dashed: held)
        let horizontal = distance.isHorizontal
        for point in [distance.start, distance.end] {
            let dx: CGFloat = horizontal ? 0 : 5
            let dy: CGFloat = horizontal ? 5 : 0
            line(from: CGPoint(x: point.x - dx, y: point.y - dy),
                 to: CGPoint(x: point.x + dx, y: point.y + dy), color: color, dashed: false)
        }
    }

    private func line(from start: CGPoint, to end: CGPoint, color: NSColor, dashed: Bool) {
        let path = NSBezierPath()
        path.move(to: start); path.line(to: end)
        path.lineWidth = 1 / scale
        if dashed { path.setLineDash([3, 3], count: 2, phase: 0) }
        if UserDefaults.standard.bool(forKey:PreferenceKey.autoContrast) {
            let halo=color.relativeLuminance > 0.45 ? NSColor.black : NSColor.white
            halo.withAlphaComponent(0.65).setStroke(); path.lineWidth=3/scale; path.stroke(); path.lineWidth=1/scale
        }
        color.setStroke(); path.stroke()
    }
    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: OverlayLabelStyle.font, .foregroundColor: OverlayLabelStyle.foreground]
    }
    private func labelWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: textAttributes).width) + 2 * OverlayLabelStyle.horizontalPadding
    }
    private func drawPill(_ text: String, in rect: CGRect, detail: String? = nil) {
        OverlayLabelStyle.drawBackground(in: rect)
        let padding = OverlayLabelStyle.horizontalPadding
        let badgeWidth = detail.map { toleranceBadgeWidth($0) } ?? 0
        let attributes = textAttributes
        let textHeight = ceil((text as NSString).size(withAttributes: attributes).height)
        let primary = CGRect(x: rect.minX + padding, y: rect.midY - textHeight / 2,
            width: max(0, rect.width - 2 * padding - badgeWidth), height: textHeight)
        (text as NSString).draw(in: primary, withAttributes: attributes)
        if let detail {
            let iconX = rect.maxX - padding - badgeWidth + Self.toleranceLeadingSpacing
            let iconSize = Self.toleranceIconSize
            let detailX = iconX + iconSize + Self.toleranceIconTextSpacing
            let icon = NSImage(systemSymbolName: "dial.low", accessibilityDescription: L("Tolerance"))?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [OverlayLabelStyle.secondaryForeground]))
            icon?.draw(in: CGRect(x: iconX, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let attributes = detailAttributes
            let detailHeight = ceil((detail as NSString).size(withAttributes: attributes).height)
            (detail as NSString).draw(in: CGRect(x: detailX, y: rect.midY - detailHeight / 2,
                width: max(0, rect.maxX - padding - detailX), height: detailHeight), withAttributes: attributes)
        }
    }
}
